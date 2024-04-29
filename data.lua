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
props.excluded.optional_if = { "included" }
props.included.optional_if = { "excluded" }
ReflectionLibraryMod.types_by_name["RotatedAnimation"].rest_optional_if = "layers"
ReflectionLibraryMod.types_by_name["RotatedSprite"].rest_optional_if = "layers"

ReflectionLibraryMod.types_by_name["RecipeData"].local_properties_by_name.results.optional_if = { "result" }

-- type is missing in data.raw.turret["small-worm-turret"].spawn_decoration[*]
ReflectionLibraryMod.types_by_name["CreateDecorativesTriggerEffectItem"].local_properties_by_name.type.optional = true

-- FootstepTriggerEffectItem's inherited properties are actually options because it can contain an array of them.
local t = ReflectionLibraryMod.types_by_name["FootstepTriggerEffectItem"]
t.rest_optional_if = "actions"

-- data.raw["noise-expression"]["0_17-lakes-elevation"].expression.arguments[3].arguments[1].arguments[1].arguments[1].arguments[1].arguments[1].arguments.points
-- is declared to be NoiseArrayConstruction but is actually a NoiseVariable.
ReflectionLibraryMod.types_by_name["NoiseArrayConstruction"].type = {
  complex_type = "union",
  options = {
    "NoiseVariable",
    { complex_type = "struct" },
  }
}

-- BoundingBox is sometimes a struct, not a tuple... but treating structs as tuples might be allowed in general?
t = ReflectionLibraryMod.types_by_name["BoundingBox"]
t.type = {
  complex_type = "union",
  options = {
    { complex_type = "struct" },
    t.type,
  }
}
t.properties = {
  {
    name = "left_top",
    type = "MapPosition",
  },
  {
    name = "right_bottom",
    type = "MapPosition",
  }
}

for _, productType in ipairs({"FluidProductPrototype", "ItemProductPrototype"}) do
  props = ReflectionLibraryMod.types_by_name[productType].local_properties_by_name
  props.amount_min.optional_if = { "amount" }
  props.amount_max.optional_if = { "amount" }
end

-- Comments were probably not intended to be required.
ReflectionLibraryMod.types_by_name["SpotNoiseArguments"].local_properties_by_name.comment.optional = true

-- TileTransitions properties all are optional when empty_transitions is true.
props = ReflectionLibraryMod.types_by_name["TileTransitions"].local_properties_by_name
props.side.optional_if = { "empty_transitions", "side_mask" }
props.side_mask.optional_if = { "empty_transitions", "side" }
props.inner_corner.optional_if = { "empty_transitions", "inner_corner_mask" }
props.inner_corner_mask.optional_if = { "empty_transitions", "inner_corner" }
props.outer_corner.optional_if = { "empty_transitions", "outer_corner_mask" }
props.outer_corner_mask.optional_if = { "empty_transitions", "outer_corner" }


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
