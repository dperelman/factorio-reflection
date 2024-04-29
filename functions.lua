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

function ReflectionLibraryMod.resolve_type(value, declaredType, deepChecks)
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
          else
            for k, v in ipairs(value) do
              if complex_type == "dictionary" then
                if not ReflectionLibraryMod.resolve_type(k, declaredType.key, deepChecks) then
                  return nil
                end
              end
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
        local resolvedOption = ReflectionLibraryMod.resolve_type(value, option)
        if resolvedOption then
          return resolvedOption
        end
      end
      -- No union member matched.
      return nil
    elseif complex_type == "type" then
      declaredType = declaredType.value
      -- Intentionally fall through to the code below handling type names.
    else
      log("ERROR: unrecognized complex_type kind: " .. complex_type);
      return nil
    end
  end

  local as_type = ReflectionLibraryMod.types_by_name[value]
  if as_type then
    local aliasedType = as_type.type
    if aliasedType.complex_type == "struct" then
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
      return ReflectionLibraryMod.resolve_type(value, aliasedType, deepChecks)
    end
  end

  local as_prototype = ReflectionLibraryMod.prototypes_by_name[value]
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
  log("ERROR: unrecognized type name: " .. declaredType);
  return nil
end

function ReflectionLibraryMod.verify_struct_properties(value, type, deepChecks)
  return not (ReflectionLibraryMod.resolve_struct_properties(value, type, deepChecks, {}) == nil)
end

function ReflectionLibraryMod.struct_declared_properties(type)
  local properties = {}

  -- Check parent properties first.
  if type.parent then
    local parentType = ReflectionLibraryMod.prototypes_by_name[type.parent]
    if not parentType then
      parentType = ReflectionLibraryMod.types_by_name[parentType]
    end
    if not parentType then
      log("Type "..type.name.." has unknown parent type "..type.parent)
      return nil
    end

    properties = ReflectionLibraryMod.struct_declared_properties(parentType)
    if not properties then
      return nil
    end
  end

  for _, prop in ipairs(type.properties) do
    -- No need to worry about overridden properties as we process subtype properties last.
    properties[prop.name] = prop
  end

  return properties
end

-- TODO Would be nice to be able to resolve just one requested property.
function ReflectionLibraryMod.resolve_struct_properties(value, type, deepChecks, overridden_props)
  local resolved = {}

  -- Check parent properties first.
  if type.parent then
    local parentType = ReflectionLibraryMod.prototypes_by_name[type.parent]
    if not parentType then
      parentType = ReflectionLibraryMod.types_by_name[parentType]
    end
    if not parentType then
      log("Type "..type.name.." has unknown parent type "..type.parent)
      return nil
    end

    local parent_overridden_props = {}
    if overridden_props then
      for propname, _ in ipairs(overridden_props) do
        parent_overridden_props[propname] = true
      end
    end
    for _, prop in ipairs(type.properties) do
      if prop.override then
        parent_overridden_props[prop.name] = true
      end
    end

    resolved = ReflectionLibraryMod.resolve_struct_properties(value, parentType, deepChecks, parent_overridden_props)
    if not resolved then
      return nil
    end
  end

  for _, prop in ipairs(type.properties) do
    -- Don't process properties overridden by subtypes.
    if not overridden_props[prop.name] then
      local propValue = value[prop.name]
      if propValue == nil then
        if not prop.optional then
          return nil
        end
      else
        local propResolvedType = not ReflectionLibraryMod.resolve_type(propValue, prop.type, deepChecks)
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
  end

  return resolved
end

function ReflectionLibraryMod.typed_object_lookup_property(typedValue, propertyName)
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

  if type.typeKind == "type" or type.typeKind == "prototype" then
    local resolvedProperties = ReflectionLibraryMod.resolve_struct_properties(typedValue.value, type.typeInfo, false, {})
    if not resolvedProperties then
      return nil
    end
    local propertyType = resolvedProperties[propertyName]
    if not propertyType then
      return nil
    end

    res.declaredType = propertyType.declaredType
    res.type = propertyName.resolvedType
    return res
  elseif type.typeKind == "literal" then
    return nil -- property lookup on a literal is nonsense
  elseif type.typeKind == "tuple" then
    if res.value == nil then
      return nil
    end

    res.declaredType = type.values[propertyName]
    if not res.declaredType then
      return nil
    end

    res.type = ReflectionLibraryMod.resolve_type(res.value, res.declaredType, false)
    return res
  elseif type.typeKind == "array" then
    if res.value == nil then
      return nil
    end

    res.declaredType = type.value
    res.type = ReflectionLibraryMod.resolve_type(res.value, res.declaredType, false)
    return res
  elseif type.typeKind == "dictionary" then
    if propertyName.func == "keys" then
      -- Instead of doing lookup, get the dictionary keys.

      res.value = {}
      for key, _ in ipairs(typedValue.value) do
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
      for _, value in ipairs(typedValue.value) do
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
      res.type = ReflectionLibraryMod.resolve_type(res.value, res.declaredType, false)
      return res
    end
  end
end

function ReflectionLibraryMod.as_typed_object(value, declaredType, valueString)
  return {
    value = value,
    declaredType = declaredType,
    root = value,
    rootString = valueString,
    path = {},
    parent = nil,
    type = ReflectionLibraryMod.resolve_type(value, declaredType)
  }
end

function ReflectionLibraryMod.typed_data_raw(prototypeTypename)
  return ReflectionLibraryMod.as_typed_object(data.raw[prototypeTypename], {
    complex_type = "array",
    value = ReflectionLibraryMod.prototypes_by_typename[prototypeTypename].name
  }, "data.raw[\""..prototypeTypename.."\"]")
end