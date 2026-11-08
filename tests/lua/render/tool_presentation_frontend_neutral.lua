--[==[psi-test
expect = "ok"
]==]
local ansi = require("psi.ansi")
local component = require("psi.tui_components.tool_execution")
local presentation =
  assert(load(
    psi.embedded_source("psi.tool_presentation"),
    nil,
    "t",
    setmetatable({
      require = function(name)
        assert(name ~= "psi.tui_component" and not name:find("psi.tui_components.", 1, true), name)
        return require(name)
      end,
    }, { __index = _G })
  ))()
local calls = {
  { "bash", { command = "printf 'hello\r\nworld'\27[31m\7", timeout = 5 } },
  { "read", { path = "README.md", offset = 3, limit = 4 } },
  {
    "write",
    {
      path = "file",
      content = string.rep("wide 世界 é ", 30) .. "\n\n" .. string.rep("line\n", 12),
    },
  },
  { "edit", { path = "file", old_text = "old", new_text = "new" }, { before_text = "old\n" } },
  { "grep", { pattern = "pattern", path = ".", glob = "*.lua", limit = 10 } },
  { "find", { pattern = "*.lua" } },
  { "ls", { path = "." } },
  { "lua", { mode = "eval", expression = "return 1" } },
  { "extension", { custom = "input" } },
}
for _, enabled in ipairs({ true, false }) do
  for _, color in ipairs({ true, false }) do
    ansi.enabled, ansi.color_enabled = enabled, color
    for _, call in ipairs(calls) do
      local execution = component.new({ tool = call[1], input = call[2], frame = call[3] })
      local expected = table.concat(execution:render(80), "\n") .. "\n"
      assert(
        presentation.render_call(table.unpack(call)) == expected,
        "legacy width-80 output: " .. call[1]
      )
      assert(component.render_call(table.unpack(call)) == expected, "compatible component export")
    end
  end
end
assert(
  require("psi.tui_components.diff").render_diff == require("psi.diff_presentation").render_diff
)
return "ok"
