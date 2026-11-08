--[==[psi-test
expect = "ok"
]==]
local keybindings = require("psi.keybindings")
local tool = require("psi.tui_components.tool_execution")
local records = require("psi.records")
local revision = keybindings.revision()
local keys = keybindings.keys
-- A getter may return fresh views without changing the binding revision.
keybindings.keys = function(id)
  local copy = {}
  for i, key in ipairs(keys(id)) do
    copy[i] = key
  end
  return copy
end
local execution = tool.new({ tool = "write", input = { content = string.rep("line\n", 12) } })
execution:set_result(records.tool_result_from_alist({ ok = true }), false)
local first = execution:render(80)
local generation = execution.generation
assert(execution:render(80) == first)
assert(execution.generation == generation, "getter identity is not a revision")
keybindings.resolved()
keybindings.conflicts()
assert(keybindings.revision() == revision, "reads must not change revision")
keybindings.reload()
assert(keybindings.revision() == revision + 1)
execution:render(80)
assert(execution.generation > generation, "reload invalidates cached presentation")
keybindings.keys = keys
return "ok"
