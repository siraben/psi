--[==[psi-test
expect = "ok"
]==]
local runtime = require("psi.tui_runtime")
local tui = require("psi.tui_status")
local fields = {
  "busy",
  "busy_kind",
  "busy_label",
  "busy_phase",
  "busy_tick",
  "busy_next_frame_at",
  "busy_started_at",
  "last_busy_paint_at",
}
local function run(active, outcome)
  local state
  local expected = {
    busy = active,
    busy_kind = active and "agent" or nil,
    busy_label = active and "thinking" or nil,
    busy_phase = 2,
    busy_tick = 17,
    busy_next_frame_at = 123,
    busy_started_at = 456,
    last_busy_paint_at = 789,
  }
  tui.register_startup_hook("clipboard-animation-test", function(context)
    state = context.state
    for _, field in ipairs(fields) do
      state[field] = expected[field]
    end
  end)
  local result = runtime._debug_edit_keys("draft", 5, { { key = "ctrl-v" } }, true, {
    clipboard_reader = function()
      if active then
        for _, field in ipairs(fields) do
          assert(state[field] == expected[field], "active operation replaced: " .. field)
        end
      else
        assert(state.busy and state.busy_kind == "clipboard")
        assert(state.busy_label == "reading clipboard")
        assert(state.busy_phase == 0 and state.busy_tick == 0)
      end
      -- Simulate host animation ticks while the cooperative reader is running.
      state.busy_phase, state.busy_tick = 3, 18
      state.busy_next_frame_at, state.last_busy_paint_at = 987, 654
      if active then
        expected.busy_phase, expected.busy_tick = 3, 18
        expected.busy_next_frame_at, expected.last_busy_paint_at = 987, 654
      end
      if outcome == "error" then
        error("reader failed")
      elseif outcome == "abort" then
        psi.abort_trigger()
      end
      return " pasted"
    end,
  })
  tui.unregister_startup_hook("clipboard-animation-test")
  for _, field in ipairs(fields) do
    assert(state[field] == expected[field], "busy state not restored: " .. field)
  end
  assert(not state.clipboard_reading)
  assert(result.input == (outcome == "ok" and "draft pasted" or "draft"))
  psi.abort_reset()
end
for _, active in ipairs({ false, true }) do
  for _, outcome in ipairs({ "ok", "error", "abort" }) do
    run(active, outcome)
  end
end
return "ok"
