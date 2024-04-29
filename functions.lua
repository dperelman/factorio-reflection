--[[
For reflection, wrap objects in TypedObject:
{
  value: -- the real raw value being wrapped
  -- Should root have a type associated with it? Maybe just be a TypedObject?
  --  Or maybe have a "parent" TypeObject instead that's just `nil` at the root?
  root: -- the root object that was the entry to the reflection library
  path: -- list of lookups to get from root to this object
        -- (special-case of some kind for keys?)
  declaredType: -- the type that appears in the prototype/type definition
                -- either a string or a table with a "complex_type" field.
  type: -- the resolved type; i.e., this will never be a union.
        -- Include reference to the prototype/type object probably?

}
--]]

function ReflectionLibraryMod.typed_value_name(typedValue)
  return typedValue.rootString.."."..table.concat(typedValue.path, ".")
end

function ReflectionLibraryMod.type_check(typedValue, deepChecks)
  if not ReflectionLibraryMod.resolve_type(typedValue.value, typedValue.declaredType, deepChecks) then
    log("ERROR: Type check failed on "..ReflectionLibraryMod.typed_value_name(typedValue))
    return false
  else
    return true
  end
end

function ReflectionLibraryMod.resolve_type(value, declaredType, deepChecks, declaringType)
  local complex_type = declaredType.complex_type
  if complex_type then
    if complex_type == "array" or complex_type == "dictionary" or complex_type == "tuple" then
      -- TODO Do any unions require more careful type checking here?
      if not (type(value) == "table") then
        return nil
      else
        if deepChecks then
          if complex_type == "tuple" then
            for k, vType in ipairs(declaredType.values) do
              local v = value[k]
              -- TODO Can tuple elements actually be optional?
              if not v and not vType.optional then
                return nil
              end
              if not ReflectionLibraryMod.resolve_type(v, vType, deepChecks) then
                return nil
              end
            end
          elseif complex_type == "dictionary" then
            for k, v in pairs(value) do
              if not ReflectionLibraryMod.resolve_type(k, declaredType.key, deepChecks) then
                return nil
              end
              if not ReflectionLibraryMod.resolve_type(v, declaredType.value, deepChecks) then
                return nil
              end
            end
          else -- complex_type == "array"
            -- Arrays should ignore non-numbered keys because
            -- https://lua-api.factorio.com/latest/prototypes/CraftingMachinePrototype.html#fluid_boxes
            -- says off_when_no_fluid_recipe is allowed as a key in its array, but only in the
            -- human-readable description, not the machine-readable section.
            for _, v in ipairs(value) do
              if not ReflectionLibraryMod.resolve_type(v, declaredType.value, deepChecks) then
                return nil
              end
            end
          end
        end

        -- Just copy all the possible fields over. Missing ones will get read and written as nil.
        return {
          typeKind = complex_type,
          -- dictionary has .key and .value
          key = declaredType.key,
          -- array has .value
          value = declaredType.value,
          -- tuple has .values
          values = declaredType.values,
        }
      end
    elseif complex_type == "literal" then
      local literalValue = declaredType.value
      if value == literalValue then
        return {
          typeKind = "literal",
          literalValue = literalValue,
        }
      else
        return nil
      end
    elseif complex_type == "union" then
      -- need to figure out which element of the union it is.
      for _, option in ipairs(declaredType.options) do
        local resolvedOption = ReflectionLibraryMod.resolve_type(value, option, deepChecks, declaringType)
        if resolvedOption then
          return resolvedOption
        end
      end
      -- No union member matched.
      return nil
    elseif complex_type == "struct" then
      -- This case means "complex_type": "struct" was used as an option inside a union in a
      -- Type's definition, which means to use the properties list on the type.
      if not declaringType then
        log("ERROR: struct doesn't make sense outside of a type definition")
        return nil
      elseif not (type(value) == "table") then
        return nil
      end

      if not ReflectionLibraryMod.verify_struct_properties(value, declaringType, deepChecks) then
        return nil
      end

      return {
        typeKind = "struct",
        name = declaringType.name,
        typeInfo = declaringType,
      }
    elseif complex_type == "type" then
      declaredType = declaredType.value
      -- Intentionally fall through to the code below handling type names.
    else
      log("ERROR: unrecognized complex_type kind: " .. complex_type)
      return nil
    end
  end

  local as_type = ReflectionLibraryMod.types_by_name[declaredType]
  if as_type then
    local aliasedType = as_type.type

    if aliasedType == "builtin" then
      local t = type(value)
      if t == "string" then
        if not (declaredType == "string") then
          return nil
        end
      elseif t == "boolean" then
        if not (declaredType == "bool") then
          return nil
        end
      elseif declaredType == "DataExtendMethod" then
        return nil
      -- The rest of the builtins are kinds of numbers: float, double, int8, int16, ...
      elseif not (t == "number") then
        return nil
      end

      return {
        typeKind = "builtin",
        name = declaredType,
        typeInfo = as_type,
      }
    elseif aliasedType.complex_type == "struct" then
      if deepChecks then
        if not ReflectionLibraryMod.verify_struct_properties(value, as_type, deepChecks) then
          return nil
        end
      end

      return {
        typeKind = "type",
        name = declaredType,
        typeInfo = as_type,
      }
    else
      local resolved = ReflectionLibraryMod.resolve_type(value, aliasedType, deepChecks, as_type)
      if resolved and resolved.typeKind == "builtin" then
        return {
          typeKind = "alias",
          name = declaredType,
          typeInfo = as_type,
        }
      end
      return resolved
    end
  end

  local as_prototype = ReflectionLibraryMod.prototypes_by_name[declaredType]
  if as_prototype then
    -- If the typename doesn't match, maybe it's a subtype.
    if not (value.type == as_prototype.typename) then
      local dynamic_prototype = ReflectionLibraryMod.prototypes_by_typename[value.type]
      if not dynamic_prototype then
        return nil
      end
      -- If the dynamic type doesn't have supertypes, it's definitely not a subtype.
      if not dynamic_prototype.parent then
        return nil
      end
      -- Look through the dynamic type's supertypes looking for the declared prototype.
      local current_prototype = dynamic_prototype
      while true do
        current_prototype = ReflectionLibraryMod.prototypes_by_name[current_prototype.parent]
        if as_prototype.typename == current_prototype.typename then
          -- We found the declared type in the supertypes, so the resolved type is the dynamic type.
          as_prototype = dynamic_prototype
          break
        elseif not current_prototype.parent then
          -- Is a prototype value of the wrong type.
          return nil
        end
      end
    end

    if deepChecks then
      if not ReflectionLibraryMod.verify_struct_properties(value, as_prototype, deepChecks) then
        return nil
      end
    end

    return {
      typeKind = "prototype",
      name = declaredType,
      typeInfo = as_prototype,
    }
  end
  -- TODO list of primitive types?

  log("ERROR: unrecognized type name: " .. declaredType)
  return nil
end

function ReflectionLibraryMod.verify_struct_properties(value, type, deepChecks)
  return not (ReflectionLibraryMod.resolve_struct_properties(value, type, deepChecks) == nil)
end

-- List of parent types with the
--  reversed=false: given type last, most general first.
--  reversed=true: given type false, most general last.
function ReflectionLibraryMod.type_and_parents(type, reversed)
  if not type.parent then
    return { type }
  end

  local parentType = ReflectionLibraryMod.prototypes_by_name[type.parent]
  if not parentType then
    parentType = ReflectionLibraryMod.types_by_name[type.parent]
  end
  if not parentType then
    log("Type "..type.name.." has unknown parent type "..type.parent)
    return nil
  end

  local types = ReflectionLibraryMod.type_and_parents(parentType, reversed)
  if not types then
    return nil
  else
    if reversed then
      table.insert(types, 1, type)
    else
      table.insert(types, type)
    end
    return types
  end
end

function ReflectionLibraryMod.struct_declared_properties(type)
  local ancestor_types = ReflectionLibraryMod.type_and_parents(type, false)
  if not ancestor_types then
    return nil
  end

  local properties = {}
  for _, t in ipairs(ancestor_types) do
    for _, prop in ipairs(t.properties) do
      -- No need to worry about overridden properties as we process subtype properties last.
      properties[prop.name] = prop
    end
  end

  return properties
end

function ReflectionLibraryMod.struct_declared_property(type, propName)
  local ancestor_types = ReflectionLibraryMod.type_and_parents(type, true)
  if not ancestor_types then
    return nil
  end

  for _, t in ipairs(ancestor_types) do
    for _, prop in ipairs(t.properties) do
      if propName == prop.name then
        return prop
      end
    end
  end

  return nil
end

function ReflectionLibraryMod.resolve_struct_properties(value, type, deepChecks)
  local declaredProperties = ReflectionLibraryMod.struct_declared_properties(type)
  if not declaredProperties then
    return nil
  end

  -- Fail fast by checking type, which is often the intentional way to distinguish unions.
  if declaredProperties.type and declaredProperties.type.type.complex_type == "literal" and
      not (declaredProperties.type.type.value == value.type) then
    return nil
  end
  -- function_name is also used to distinguish unions
  if declaredProperties.function_name and declaredProperties.function_name.type.complex_type == "literal" and
      not (declaredProperties.function_name.type.value == value.function_name) then
    return nil
  end

  local resolved = {}
  for _, prop in pairs(declaredProperties) do
    local propValue = value[prop.name]
    if propValue == nil then
      if not prop.optional then
        return nil
      end
    else
      local propResolvedType = ReflectionLibraryMod.resolve_type(propValue, prop.type, deepChecks)
      if not propResolvedType then
        return nil
      else
        resolved[prop.name] = {
          declaredType = prop.type,
          resolvedType = propResolvedType,
        }
      end
    end
  end

  return resolved
end

function ReflectionLibraryMod.typed_object_lookup_property(typedValue, propertyName)
  if not (type(typedValue.value) == "table") then
    return nil
  end

  local type = typedValue.type
  local newPath = {}
  for index, value in ipairs(typedValue.path) do
    newPath[index] = value
  end
  table.insert(newPath, propertyName)

  local res = {
    -- TODO What happens here if propertyName is a table?
    value = typedValue.value[propertyName],
    root = typedValue.root,
    rootString = typedValue.rootString,
    path = newPath,
    parent = typedValue,
  }

  if res.value == nil and not propertyName.func then
    return nil
  end

  if type.typeKind == "type" or type.typeKind == "prototype" or type.typeKind == "struct" then
    local prop = ReflectionLibraryMod.struct_declared_property(type.typeInfo, propertyName)
    if not prop then
      return nil
    end

    res.declaredProperty = prop
    res.declaredType = prop.type
  elseif type.typeKind == "literal" then
    return nil -- property lookup on a literal is nonsense
  elseif type.typeKind == "tuple" then
    res.declaredType = type.values[propertyName]
    if not res.declaredType then
      return nil
    end
  elseif type.typeKind == "array" then
    if res.value == nil then
      return nil
    end

    res.declaredType = type.value
  elseif type.typeKind == "dictionary" then
    if propertyName.func == "keys" then
      -- Instead of doing lookup, get the dictionary keys.

      res.value = {}
      for key, _ in pairs(typedValue.value) do
        table.insert(res.value, key)
      end

      res.declaredType = {
        complex_type = "array",
        value = type.key
      }
      res.type = {
        typeKind = "array",
        value = type.key,
      }

      return res
    elseif propertyName.func == "values" then
      -- Instead of doing lookup, get the dictionary values.

      res.value = {}
      for _, value in pairs(typedValue.value) do
        table.insert(res.value, value)
      end

      res.declaredType = {
        complex_type = "array",
        value = type.value
      }
      res.type = {
        typeKind = "array",
        value = type.value,
      }

      return res
    else
      -- otherwise, property name should be a key
      if res.value == nil then
        return nil
      end

      res.declaredType = type.value
    end
  end

  res.type = ReflectionLibraryMod.resolve_type(res.value, res.declaredType, false)
  return res
end

function ReflectionLibraryMod.as_typed_object(value, declaredType, valueString, wrappingType)
  return {
    value = value,
    declaredType = declaredType,
    root = value,
    rootString = valueString,
    path = {},
    parent = nil,
    type = ReflectionLibraryMod.resolve_type(value, declaredType, false, wrappingType)
  }
end

function ReflectionLibraryMod.typed_data_raw_section(prototypeTypename)
  local value = data.raw[prototypeTypename]
  if not value then
    -- Prototype not actually in data.raw?
    return nil
  end

  return ReflectionLibraryMod.as_typed_object(value, {
    complex_type = "array",
    value = ReflectionLibraryMod.prototypes_by_typename[prototypeTypename].name
  }, "data.raw[\""..prototypeTypename.."\"]")
end

local prototype = {}
local mt = {}
mt.__index = function (table, key)
  local res = prototype[key] or ReflectionLibraryMod.wrap_typed_object(
    ReflectionLibraryMod.typed_object_lookup_property(table._private, key))
  if res == nil then
    if key == "_value" then
      res = table._private.value
    elseif key == "_type" then
      res = table._private.type
    elseif key == "_parent" then
      res = ReflectionLibraryMod.wrap_typed_object(table._private.parent)
    elseif key == "_propertyInfo" then
      res = table._private.declaredProperty
    end
  end
  return res
end

mt.__newindex = function (table, key, newValue)
  -- If newValue is a wrapped typed value, then unwrap it before using it.
  if getmetatable(newValue) == mt then
    newValue = newValue._private.value
  end
  table._private.value[key] = newValue
end

mt.__tostring = function (table)
  return tostring(table._private.value)
end

if (__DebugAdapter) then
  local variables = require('__debugadapter__/variables.lua')
  local iterutil = require('__debugadapter__/iterutil.lua')

  mt.__debugline = function (table, short)
    return variables.describe(table._private.value, short)
  end

  local specialKeys = {
    "_type",
    "_propertyInfo",
    "_parent",
    "_path()",
    "_pathString()",
    "_keys()",
    "_values()",
    "_value",
  }
  local lastSpecialKey = specialKeys[#specialKeys]
  mt.__debugcontents = function (table)
    function stateless_iter(table, k)
      if not k or not (k == lastSpecialKey) and string.sub(k, 1, 1) == "_" then
        local seenKey = k == nil
        for _, nextKey in ipairs(specialKeys) do
          if not seenKey then
            if nextKey == k then
              seenKey = true
            end
          else
            local v
            if string.sub(nextKey, -2) == "()" then
              local funcName = string.sub(nextKey, 1, -3)
              v = table[funcName](table)
            else
              v = table[nextKey]
            end
            if not (v == nil) then
              return nextKey, v
            end
          end
        end
      end

      if k == lastSpecialKey then
        k = nil
      end

      if type(table._private.value) == "table" then
        -- Show debug display in property order if possible.
        local typeInfo = table._private.type.typeInfo
        -- TODO Handle ordering parent properties?
        if (typeInfo and typeInfo.properties and not typeInfo.parent) then
          local seenKey = k == nil
          for _, prop in ipairs(typeInfo.properties) do
            if not seenKey then
              if prop.name == k then
                seenKey = true
              end
            else
              local v = mt.__index(table, prop.name)
              if nil~=v then
                return prop.name, v
              end
            end
          end
          return nil, nil
        end

        local v
        k, v = next(table._private.value, k)
        if nil~=v then
          -- This could return nil on a type error...
          return k,mt.__index(table, k)
        end
      end
    end

    return stateless_iter, table, nil
  end
end

prototype._keys = function (table)
  return mt.__index(table, { func="keys" })
end

prototype._values = function (table)
  return mt.__index(table, { func="values" })
end

-- From http://lua-users.org/wiki/GeneralizedPairsAndIpairs
mt.__pairs = function (table)
  -- Iterator function takes the table and an index and returns the next index and associated value
  -- or nil to end iteration

  local function stateless_iter(table, k)
    if type(table._private.value) == "table" then
      local v
      k, v = next(table._private.value, k)
      if nil~=v then
        -- This could return nil on a type error...
        return k,mt.__index(table, k)
      end
    end
  end

  -- Return an iterator function, the table, starting point
  return stateless_iter, table, nil
end

mt.__ipairs = function (table)
  -- Iterator function
  local function stateless_iter(table, i)
    if type(table._private.value) == "table" then
      i = i + 1
      local v = mt.__index(table, i)
      if nil~=v then return i, v end
    end
  end

  -- return iterator function, table, and starting point
  return stateless_iter, table, 0
end

prototype._type_check = function (table, deepChecks)
  return ReflectionLibraryMod.type_check(table._private, deepChecks)
end

prototype._path = function (wrappedValue)
  local fullPath = { wrappedValue._private.rootString }
  for _, section in ipairs(wrappedValue._private.path) do
    table.insert(fullPath, section)
  end
  return fullPath
end

local luaKeywords = {
  ["and"] = true,
  ["break"] = true,
  ["do"] = true,
  ["else"] = true,
  ["elseif"] = true,
  ["end"] = true,
  ["false"] = true,
  ["for"] = true,
  ["function "] = true,
  ["if"] = true,
  ["in"] = true,
  ["local"] = true,
  ["nil"] = true,
  ["not"] = true,
  ["or"] = true,
  ["repeat"] = true,
  ["return"] = true,
  ["then"] = true,
  ["true"] = true,
  ["until"] = true,
  ["while"] = true,
}

function ReflectionLibraryMod.is_valid_lua_identifier(str)
  return string.match(str, "^[_%a][_%a%d]*$") and not luaKeywords[str]
end

prototype._pathString = function (table)
  local pathString = table._private.rootString
  for _, section in ipairs(table._private.path) do
    if section.func then
      pathString = pathString .. ":" .. section.func .. "()"
    elseif ReflectionLibraryMod.is_valid_lua_identifier(section) then
      pathString = pathString .. "." .. section
    else -- this doesn't bother with checking if section needs to be escaped
      pathString = pathString .. "[\"" .. section .. "\"]"
    end
  end
  return pathString
end

function ReflectionLibraryMod.wrap_typed_object(typedValue)
  if typedValue == nil then
    return nil
  end

  local res = {_private = typedValue}
  setmetatable(res, mt)

  return res
end
