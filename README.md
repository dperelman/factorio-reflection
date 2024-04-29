# Factorio Reflection Library

This is an early work-in-progress. See [Description](./description.md)
for how to use it.

The goal of this mod is to give runtime access to
https://lua-api.factorio.com/latest/auxiliary/json-docs-prototype.html
thereby allowing mods to get the types of Lua values as given in the
documentation instead of just `"string"` or `"table"` as available from Lua.
This will include having helper functions to walk `data.raw` with type
information.

This information may be useful to mods that want to do certain mass operations
over all of `data.raw` like
[exfret's randomizer](https://mods.factorio.com/mod/propertyrandomizer) or
[Pacifist](https://mods.factorio.com/mod/Pacifist).

This repository does not contain the prototypes information. The script
[`convert_to_lua.sh`](./convert_to_lua.sh) downloads the JSON, installs
[an `npm` script to convert it to Lua](https://github.com/dperelman/json2lua/tree/feature/string-escaping)
and runs that script to generate `prototype-api.lua`.
