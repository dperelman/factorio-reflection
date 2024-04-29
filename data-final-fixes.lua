require("__ReflectionLibrary__.functions")

log("In ReflectionLibrary...")

for typename, _ in pairs(ReflectionLibraryMod.prototypes_by_typename) do
  log("Loading data.raw[\""..typename.."\"]...")
  local typedValue = ReflectionLibraryMod.typed_data_raw(typename)
  log("Type checking data.raw[\""..typename.."\"]...")
  ReflectionLibraryMod.type_check(typedValue, true)
  log("Passed type check: data.raw[\""..typename.."\"]!")
end