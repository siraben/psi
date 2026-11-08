--[==[psi-test
expect = "ok"
]==]
local registry = require("psi.api_registry")
registry.model = function(id)
  if id == "openrouter/vendor/vision" or id == "openai-codex/vendor/vision" then
    return { input = { "image" } }
  elseif id == "openrouter/vendor/text" or id == "openai-codex/vendor/text" then
    return { input = { "text" } }
  end
end
local path = TMP .. "/tiny.png"
assert(psi.file_write(path, "\137PNG\r\n\26\n\0\0\0\13IHDR" .. string.rep("\0", 17)))
local tools = require("psi.tools")
local session = require("psi.session_manager")
local codex = require("psi.providers.openai_codex")._debug
local router = require("psi.providers.openrouter")._debug
session.append_assistant("", {
  { type = "tool_use", id = "call|item", name = "read", input = { path = path } },
}, {})
session.append_tool_result("call|item", "read", "{}", false, {
  { type = "image", mimeType = "image/png", data = "abc" },
})
for _, model in ipairs({ "vendor/vision", "vendor/text", "vendor/unknown" }) do
  for _, qualified in ipairs({ false, true }) do
    for _, provider in ipairs({ "openrouter", "openai-codex" }) do
      local id = qualified and provider .. "/" .. model or model
      local result = tools.dispatch("read", { path = path }, { provider = provider, model = id })
      assert(result.ok)
      local warned = result.extras.text:find("does not support images", 1, true) ~= nil
      assert(warned == (model == "vendor/text"), "read retains unknown fallback")
      if provider == "openrouter" then
        assert(router.make_config(id).supports_images == (model == "vendor/vision"))
      else
        local input = codex.response_input_from_session(session.messages(), "", nil, id)
        assert((type(input[2].output) == "table") == (model == "vendor/vision"))
      end
    end
  end
end
return "ok"
