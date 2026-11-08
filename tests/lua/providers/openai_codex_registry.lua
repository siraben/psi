--[==[psi-test
expect = "ok"
]==]
local registry = require("psi.api_registry")
local capabilities = require("psi.provider_capabilities")
local count, image_models, text_only_models = 0, 0, 0
for _, model in ipairs(registry.all_models()) do
  if model.provider == "openai-codex" then
    count = count + 1
    local desc = registry.resolve_descriptor(model.id)
    assert(registry.resolve_route(model.id).name == "openai-codex")
    assert(desc.provider == "openai-codex" and desc.api == "openai-codex-responses")
    assert(desc.id == model.id:match("^openai%-codex/(.+)$"))
    assert(type(model.context_window) == "number" and model.context_window > 0)
    assert(model.supports_tool_use == true)
    local modalities = {}
    for _, modality in ipairs(model.input) do modalities[modality] = true end
    assert(modalities.text, "Codex models must accept text")
    local images = capabilities.supports_images("openai-codex", desc.id)
    assert(images == (modalities.image == true))
    if images then image_models = image_models + 1 else text_only_models = text_only_models + 1 end
  end
end
assert(count > 0 and image_models > 0 and text_only_models > 0,
  "catalogue must exercise image-capable and text-only Codex models")
return "ok"
