--[==[psi-test
expect = "ok"
env = { HOME = "{TMP}/keybindings-home" }
files = [
  { path = "keybindings-home/.config/psi/keybindings.json", json = { "tui.queue.previous" = "ctrl-p" } },
]
]==]
local agent = require("psi.agent_session")
local runtime = require("psi.tui_runtime")
local payload = string.rep("payload $1%", 100)
local function events(tail)
  local out = {
    { key = "paste-start" },
    { key = "text", text = payload },
    { key = "paste-end" },
  }
  for _, event in ipairs(tail) do
    out[#out + 1] = event
  end
  return out
end
local undo = runtime._debug_edit_keys(
  "",
  0,
  events({
    { key = "backspace" },
    { key = "ctrl--" },
  }),
  false
)
assert(undo.expanded_input == payload and undo.paste_count == 1, "undo restores payload registry")
local yank = runtime._debug_edit_keys(
  "",
  0,
  events({
    { key = "ctrl-u" },
    { key = "ctrl-y" },
  }),
  false
)
assert(yank.expanded_input == payload, "kill ring stores payload, not marker")
agent.clear_queues()
agent.queue_follow_up("queued")
local draft = runtime._debug_edit_keys(
  "",
  0,
  events({
    { key = "ctrl-p" },
    { key = "text", text = " edit" },
    { key = "enter" },
  }),
  false,
  { busy = true }
)
assert(agent.pending_message(1).text == "queued edit")
assert(
  draft.expanded_input == payload and draft.paste_count == 1,
  "queue edit restores draft payload"
)
assert(draft.queue_nav_index == nil)
agent.clear_queues()
return "ok"
