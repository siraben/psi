-- Lazy registry access avoids provider/registry initialization cycles.
local M = {}

-- provider identifies the namespace; local_model_id may contain slashes or
-- already carry that same provider prefix. Without provider it is a registry id.
-- nil means unknown, distinct from a known model without image input.
function M.supports_images(provider, local_model_id)
  if type(local_model_id) ~= "string" or local_model_id == "" then
    return nil
  end
  local id = local_model_id
  if type(provider) == "string" and provider ~= "" then
    local prefix = provider .. "/"
    if id:sub(1, #prefix) ~= prefix then
      id = prefix .. id
    end
  end
  -- Registry load failures retain the callers' unknown-model policy.
  local ok, registry = pcall(require, "psi.api_registry")
  local model = ok and registry and registry.model and registry.model(id) or nil
  local input = type(model) == "table" and model.input or nil
  if type(input) ~= "table" then
    return nil
  end
  for _, modality in ipairs(input) do
    if modality == "image" then
      return true
    end
  end
  return false
end

return M
