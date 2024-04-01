#!/bin/sh
json=prototype-api.json
if [ ! -f "$json" ]
then
    wget https://lua-api.factorio.com/latest/prototype-api.json
fi
lua=prototype-api.lua
echo "ReflectionLibraryMod.prototype_api =" > "$lua"
temp=$(mktemp)
# Original does not handle strings correctly, so use my branch.
#npm install json2lua
npm install git+https://github.com/dperelman/json2lua.git\#feature/string-escaping
npx json2lua "$json" "$temp"
cat "$temp" >> "$lua"
rm "$temp"
