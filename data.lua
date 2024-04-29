ReflectionLibraryMod = ReflectionLibraryMod or {}
require("__ReflectionLibrary__.prototype-api")

ReflectionLibraryMod.prototypes_by_name = {}
ReflectionLibraryMod.prototypes_by_typename = {}
for _, value in ipairs(ReflectionLibraryMod.prototype_api.prototypes) do
  ReflectionLibraryMod.prototypes_by_name[value.name] = value

  -- Abstract prototypes don't have typenames.
  if value.typename then
    ReflectionLibraryMod.prototypes_by_typename[value.typename] = value
  end
end

ReflectionLibraryMod.types_by_name = {}
for _, value in ipairs(ReflectionLibraryMod.prototype_api.types) do
  ReflectionLibraryMod.types_by_name[value.name] = value
end

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
