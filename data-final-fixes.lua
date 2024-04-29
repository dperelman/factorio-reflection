require("__ReflectionLibrary__.functions")

log("In ReflectionLibrary...")

for typename, _ in pairs(ReflectionLibraryMod.prototypes_by_typename) do
  log("Loading data.raw[\""..typename.."\"]...")
  local typedValue = ReflectionLibraryMod.typed_data_raw_section(typename)
  if not typedValue then
    log("No entry data.raw[\""..typename.."\"].")
  else
    log("Type checking data.raw[\""..typename.."\"]...")
    if ReflectionLibraryMod.type_check(typedValue, true) then
      log("Passed type check: data.raw[\""..typename.."\"]!")
    end
  end
end