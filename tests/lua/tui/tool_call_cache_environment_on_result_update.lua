--[==[psi-test
expect = "ok"
cwd = "tool-call-cache"
files = [
  { path = ".psi/keybindings.json", json = { "app.tools.expand" = "ctrl-b" } },
]
]==]
local ansi = require("psi.ansi")
local keybindings = require("psi.keybindings")
local records = require("psi.records")
local tool = require("psi.tui_components.tool_execution")
local text = require("psi.tui_text")
ansi.enabled, ansi.color_enabled = true, true
local input = { path = "file", content = string.rep("line\n", 12) }
local result = records.tool_result_from_alist({ ok = true })
local execution = tool.new({ tool = "write", input = input })
local function update_and_check()
  -- Result updates can arrive before the next frame notices a style change.
  execution:set_result(result, false)
  local actual = table.concat(execution:render(80), "\n")
  local fresh = tool.new({ tool = "write", input = input, result = result })
  assert(actual == table.concat(fresh:render(80), "\n"), "call cache reused stale rendering inputs")
  return actual
end
ansi.enabled = false
assert(not update_and_check():find("\27", 1, true))
ansi.enabled = true
update_and_check()
ansi.color_enabled = false
update_and_check()
ansi.color_enabled = true
update_and_check()
ansi.set_code_map({ ["36"] = "35" })
update_and_check()
assert(psi.file_write(".psi/keybindings.json", '{"app.tools.expand":"ctrl-o"}'))
keybindings.reload()
local rebound = text.strip_ansi(update_and_check())
assert(rebound:find("ctrl+o to expand", 1, true))
assert(not rebound:find("ctrl+b", 1, true))
return "ok"
