ReflectionLibraryMod = ReflectionLibraryMod or {}
require("__ReflectionLibrary__.prototype-api")

local function add_local_properties_by_name(value)
  -- TODO Include supertype properties/info?
  if value.properties then
    value.local_properties_by_name = {}

    for _, prop in ipairs(value.properties) do
      value.local_properties_by_name[prop.name] = prop
    end
  end
end

ReflectionLibraryMod.prototypes_by_name = {}
ReflectionLibraryMod.prototypes_by_typename = {}
for _, value in ipairs(ReflectionLibraryMod.prototype_api.prototypes) do
  add_local_properties_by_name(value)

  ReflectionLibraryMod.prototypes_by_name[value.name] = value

  -- Abstract prototypes don't have typenames.
  if value.typename then
    ReflectionLibraryMod.prototypes_by_typename[value.typename] = value
  end
end

ReflectionLibraryMod.types_by_name = {}
for _, value in ipairs(ReflectionLibraryMod.prototype_api.types) do
  add_local_properties_by_name(value)

  ReflectionLibraryMod.types_by_name[value.name] = value
end


-- Monkey patch apparently incorrect documentation
local props = ReflectionLibraryMod.prototypes_by_name["DontUseEntityInEnergyProductionAchievementPrototype"].local_properties_by_name
props.excluded.optional = true
props.included.optional = true


local data_raw_properties = {}
for typename, prototype in pairs(ReflectionLibraryMod.prototypes_by_typename) do
  table.insert(data_raw_properties, {
    name = typename,
    optional = true,
    type = {
      complex_type = "dictionary",
      key = "string",
      value = prototype.name,
    },
  })
end
ReflectionLibraryMod.data_raw_type = {
  name = "_type_of_data.raw",
  type = { complex_type = "struct" },
  properties = data_raw_properties
}

require("__ReflectionLibrary__.functions")

local typed_data_raw = ReflectionLibraryMod.wrap_typed_object(
  ReflectionLibraryMod.as_typed_object(data.raw, ReflectionLibraryMod.data_raw_type.type,
                                       "data.raw", ReflectionLibraryMod.data_raw_type))
if not typed_data_raw then
  error("Failed to load ReflectionLibrary: data.raw type checking failed.")
else
  ReflectionLibraryMod.typed_data_raw = typed_data_raw
end
