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
