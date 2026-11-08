--[==[psi-test
expect = "ok"
]==]
local session = require("psi.session_manager")
local path = TMP .. "/failure.jsonl"
session.append_user("first")
local writes = 0
local atomic = psi.file_write_atomic
psi.file_write_atomic = function(p, data, mode)
  assert(p == path and mode == 384 and data:sub(-1) == "\n")
  writes = writes + 1
  return false
end
local ok, err = session.save(path)
assert(not ok and err == "Failed to create session " .. path)
psi.file_write_atomic = function(p, data, mode)
  writes = writes + 1
  return atomic(p, data, mode)
end
assert(session.save(path) and writes == 2)
assert(session.save(path) and writes == 2, "successful retry restores no-op bookkeeping")
local contents = psi.read_file(path)
assert(contents:find("first", 1, true))
psi.file_write_atomic = nil
local open = io.open
local closed = 0
io.open = function(_, mode)
  assert(mode == "w")
  return setmetatable({
    write = function()
      error("injected write failure", 0)
    end,
  }, {
    __close = function()
      closed = closed + 1
    end,
  })
end
ok, err = session.save(TMP .. "/fallback.jsonl")
assert(not ok and err == "injected write failure" and closed == 1)
io.open = function()
  return nil, "injected open failure"
end
ok, err = session.save(TMP .. "/fallback.jsonl")
assert(not ok and err == "injected open failure")
io.open = open
assert(session.save(TMP .. "/fallback.jsonl"))
assert(psi.read_file(TMP .. "/fallback.jsonl"):find("first", 1, true))
-- Empty fork uses the message-converting writer, not the raw-entry writer.
assert(session.fork(0, TMP .. "/empty.jsonl"))
local n = 0
for _ in psi.read_file(TMP .. "/empty.jsonl"):gmatch("[^\n]+") do
  n = n + 1
end
assert(n == 1)
local messages = psi.session_messages
psi.session_messages = function()
  return { { role = "user", text = "legacy message" }, { role = "assistant", text = "unused" } }
end
for _, use_atomic in ipairs({ false, true }) do
  psi.file_write_atomic = use_atomic and atomic or nil
  local fork_path = TMP .. "/legacy-" .. tostring(use_atomic) .. ".jsonl"
  assert(session.fork(1, fork_path))
  local lines = {}
  for line in psi.read_file(fork_path):gmatch("[^\n]+") do
    lines[#lines + 1] = psi.json_decode(line, true)
  end
  assert(#lines == 2 and lines[1].type == "session" and lines[2].type == "message")
  assert(lines[2].message.role == "user" and lines[2].message.content[1].text == "legacy message")
end
psi.file_write_atomic = function()
  return false
end
ok, err = session.fork(1, path)
assert(not ok and err == "Failed to create session " .. path)
psi.file_write_atomic = nil
io.open = function()
  return setmetatable({
    write = function()
      error("conversion writer failure", 0)
    end,
  }, {
    __close = function()
      closed = closed + 1
    end,
  })
end
ok, err = session.fork(1, path)
assert(not ok and err == "conversion writer failure" and closed == 2)
io.open, psi.session_messages = open, messages
return "ok"
