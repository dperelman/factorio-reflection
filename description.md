This mod provides programmatic access to the machine-readable [Prototype JSON](https://lua-api.factorio.com/latest/auxiliary/json-docs-prototype.html) during the data phase. To use, add a dependency on this mod and reference `ReflectionLibraryMod.typed_data_raw`, which can be used just like you would use `data.raw` with some additional features:
 * `._value`: the underlying value; this is the escape hatch from this library.
 * `._type`: the resolved type of the value. `._type.typeKind` determines what other properties are available (note types referenced inside this object are just strings of the type name; this may be improved in a future version):
    * `typeKind = "literal"`: only one value is allowed and it's in `._type.literalValue`
    * `typeKind = "array"`: array of values of type `._type.value`
    * `typeKind = "tuple"`: tuple of values with the type for each entry given by the array `._type.values`
    * `typeKind = "dictionary"`: dictionary where all keys are of type `._type.key` and all values are of type `._type.value`
    * All of the remaining types have `._type.name` and `._type.typeInfo` giving the details.
    * `typeKind = "builtin"`: a built-in primitive type like `"string"` or `"int8"`
    * `typeKind = "alias"`: an alias to a built-in type, which may give more semantics like `"EntityID"`
    * `typeKind = "prototype"`: a prototype
    * `typeKind = "type"`: a type being used as its own properties
    * `typeKind = "struct"`: a type that's defined as a union, but being used as its own properties
 * `._propertyInfo`: if this is a property, then the property information from the JSON
 * `._parent`: if this is not the root, then the typed object containing this (e.g. `typed_data_raw.car._parent` is `typed_data_raw`)
 * `._pathString()`: approximately the Lua code to get this value starting from `data.raw` (e.g. `typed_data_raw.car.tank._path() == "data.raw.car.tank"`)
 * `._path()`: same as above, but as an array of keys to lookup (e.g. `typed_data_raw.car.tank._path() == { "data.raw", "car", "tank" }`)
 * `._keys()`: on a dictionary, gets an array of the keys as a typed object
 * `._values()`: on a dictionary, gets an array of the values as a typed object
 * `._typeCheck(isDeep)`: attempts to verify all of the types are
     correct on the given typed object. If `isDeep` is true, it will
     descend into all of its children. If the type check fails,
     `error()` will be called, so use `pcall` if you don't want Factorio
     to crash. This method mainly exists to test the library, users of
     the library probably will not want to call it.

`pairs()`/`ipairs()` will work on typed objects as you'd expect,
ignoring those `_*` properties, although those properties will appear in
the debugger. Additionally, assignment will work as expected and the
type information will be automatically updated:
```lua
local bbook = data_raw['blueprint-book']['blueprint-book']
log(bbook.inventory_size._type.typeKind)  # prints "literal"
bbook.inventory_size = 42
log(bbook.inventory_size._type.typeKind)  # prints "alias"
log(bbook.inventory_size._type.name)      # prints "ItemStackIndex"
```


The prototype JSON is loaded into `ReflectionLibraryMod.prototype_api`.
For ease of use, the following dictionaries are defined:
 * `ReflectionLibraryMod.prototypes_by_name`
 * `ReflectionLibraryMod.prototypes_by_typename`
 * `ReflectionLibraryMod.types_by_name`

Also, all of the prototypes/types have an additional property
`.local_properties_by_name` that you use use instead of `.properties`.


This mod is a work-in-progress. I welcome feedback (and pull requests)
on what would be useful and what would be a better API design. And
code style improvement as this is by far the largest Lua project I've
written.


TODO:
 * Fix sort order of properties in debugger.
 * Add reference following for `*ID` types so, for example, given an
     `EntityID`, you could get the `EntityPrototype` it references.
 * Look into making the `_type` object more user friendly, so the user
     doesn't need to know about the prototypes/types dictionaries normally.
 * Add a helper to search for values by type (or collection of types).
 * Generally refactor and cleanup code.
