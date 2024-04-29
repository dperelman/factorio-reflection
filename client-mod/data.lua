require("__ReflectionLibrary__.functions")

log("In ReflectionClient...")

local data_raw = ReflectionLibraryMod.typed_data_raw

local bbook = data_raw['blueprint-book']['blueprint-book']
bbook:_type_check(true)
bbook.inventory_size = 42
bbook:_type_check(true)

for typename, typedValue in pairs(ReflectionLibraryMod.typed_data_raw) do
  log("Client: Loading typed_data_raw[\""..typename.."\"]...")
  if not typedValue then
    log("Client: No entry data.raw[\""..typename.."\"].")
  else
    for _, value in pairs(typedValue) do
      value:_type_check(true)
    end
  end
end