-- xAI's OpenAI-compatible Chat Completions API.
local auth = require("psi.providers.oauth_xai")
local storage = require("psi.auth_storage")
local chat = require("psi.providers.openrouter")
local compat = require("psi.providers.openai_compat")
local capabilities = require("psi.provider_capabilities")
local registry = require("psi.api_registry")
local M = {}

function M.has_auth()
  return storage.has_api_key("xai", "XAI_API_KEY") or auth.has_credentials()
end

local function config(opts)
  local key, err = storage.resolve_api_key("xai", "XAI_API_KEY")
  if not key then
    key, err = auth.access_token()
  end
  if not key or key:find("[%c%s]") then
    return nil, err or "Invalid xAI credential"
  end
  opts.model = registry.resolve_model("xai", opts.model)
  return chat.chat_config({
    provider = "xai",
    api = "xai-chat-completions",
    url = "https://api.x.ai/v1/chat/completions",
    headers = { "Content-Type: application/json", "Authorization: Bearer " .. key },
    supports_images = capabilities.supports_images("xai", opts.model) == true,
  })
end

function M.run_turn(opts)
  local cfg, err = config(opts)
  if not cfg then
    return false, err
  end
  return compat.run_turn(opts, cfg)
end

function M.complete_text(opts)
  local cfg, err = config(opts)
  if not cfg then
    return false, err
  end
  return compat.complete_text(opts, cfg)
end

return M
