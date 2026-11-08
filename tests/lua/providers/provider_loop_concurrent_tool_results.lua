--[==[psi-test
expect = "ok"
]==]
local loop = require("psi.provider_loop")
local sched = require("psi.sched")
local session = require("psi.session_manager")
local helpers = require("psi.tool_helpers")
local records = require("psi.records")
local calls, started, completed, observed = {}, {}, {}, {}
for i = 1, 3 do
  calls[i] = { type = "tool_use", id = "distinct-" .. i, name = "overlap_probe", input = { index = i } }
end
helpers.register({
  name = "overlap_probe",
  description = "local scheduler probe",
  input_schema = helpers.schema_object({}, {}),
  impl = function(input, meta)
    local i = input.index
    assert(meta.tool_call_id == calls[i].id)
    assert(sched.in_coroutine())
    started[i] = true
    -- All three must enter before any can finish. Bounded yields fail a serial
    -- dispatcher without relying on wall-clock speed or network latency.
    for _ = 1, 20 do
      if started[1] and started[2] and started[3] then break end
      sched.sleep_ms(1)
    end
    assert(started[1] and started[2] and started[3], "parallel tool calls did not overlap")
    completed[i] = true
    return records.tool_success("overlap_probe", { output = "result-" .. i })
  end,
})
psi.session_set_path(TMP .. "/parallel.jsonl")
session.append_user("run local tools")
local requests = 0
psi.http_stream_begin = function()
  requests = requests + 1
  assert(requests <= 2)
  return {}
end
psi.http_stream_poll = function() return nil, true end
psi.http_stream_finish = function() return 200 end
local ok, text = sched.run(function()
  return loop.run_turn({
    max_retries = 0,
    observer = {
      on_tool_result = function(id, name, json)
        assert(not observed[id], "duplicate result observation")
        assert(name == "overlap_probe")
        local i = assert(tonumber(id:match("^distinct%-(%d)$")))
        local result = psi.json_decode(json)
        assert(completed[i] and result.ok and result.output == "result-" .. i)
        observed[id] = true
      end,
    },
  }, {
    provider_name = "local-probe", url = "https://example.invalid", headers = {},
    tool_specs = function() return {} end,
    build_messages = function(messages) return messages end,
    request_body = function(args) return { messages = args.messages } end,
    new_state = function() return {} end,
    parser_new = function() return {} end,
    parser_push = function() end,
    finalize = function()
      if requests == 1 then return "", calls end
      return "done", {}
    end,
    persist = function(_, _, content, tool_calls)
      session.append_assistant(content, tool_calls)
    end,
    text = function() return requests == 2 and "done" or "" end,
  })
end)
assert(ok and text == "done" and requests == 2)
local result_count = 0
for _, message in ipairs(session.messages()) do
  if message.role == "tool-result" then
    result_count = result_count + 1
    local body = psi.json_decode(message.data).message
    local id = calls[result_count].id
    assert(body.toolCallId == id and observed[id], "persist results in original call order")
    assert(psi.json_decode(message.text).output == "result-" .. result_count)
  end
end
assert(result_count == 3)
local durable = assert(psi.read_file(TMP .. "/parallel.jsonl"))
local durable_count = 0
for line in durable:gmatch("[^\n]+") do
  local message = psi.json_decode(line).message
  if message and message.role == "toolResult" then
    durable_count = durable_count + 1
    assert(message.toolCallId == calls[durable_count].id)
    assert(psi.json_decode(message.content[1].text).output == "result-" .. durable_count)
  end
end
assert(durable_count == 3)
return "ok"
