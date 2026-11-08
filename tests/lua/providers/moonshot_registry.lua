--[==[psi-test
expect = "ok"
]==]
local registry = require("psi.api_registry")
local count = 0
for _, model in ipairs(registry.all_models()) do
  if model.provider == "moonshot" then
    count = count + 1
    local route = registry.resolve_route(model.id)
    local desc = registry.resolve_descriptor(model.id)
    assert(route.name == "moonshot")
    assert(desc.api == "moonshot-messages")
    assert(desc.compat.thinking_format == "anthropic")
    assert(desc.compat.supports_tool_use)
    assert(desc.model == model.id:match("^moonshot/(.+)$"))
  end
end
assert(count > 0, "Moonshot catalogue must be routable")
return "ok"
