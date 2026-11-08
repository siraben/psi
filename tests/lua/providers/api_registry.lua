--[==[psi-test
expect = "ok"
]==]
local registry = require("psi.api_registry")
local apis = {}
for _, api in ipairs(registry.all_apis()) do
  assert(not apis[api.name], "duplicate API")
  apis[api.name] = api
end
for _, name in ipairs({ "anthropic-messages", "ollama-chat", "openrouter-chat-completions",
  "openai-codex-responses", "moonshot-messages" }) do
  assert(apis[name], "missing supported wire API: " .. name)
end
for _, provider in ipairs(registry.all_providers()) do
  assert(apis[provider.api], "provider must route to a registered API")
  local id = provider.name .. "/" .. provider.default_model
  local route = registry.resolve_route(id)
  local descriptor = registry.resolve_descriptor(id)
  assert(route.name == provider.name)
  assert(descriptor.provider == provider.name and descriptor.api == provider.api)
  assert(descriptor.id == provider.default_model)
end
return "ok"
