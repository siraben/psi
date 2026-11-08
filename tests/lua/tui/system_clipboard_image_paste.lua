--[==[psi-test
expect = "a /tmp/capture.png b|19|0|aTEXTb|5|1|afallbackb|9|1"
]==]
local rt = require("psi.tui_runtime")

local image_text_reads = 0
local pasted_image = rt._debug_edit_keys("ab", 1, { { key = "ctrl-v" } }, false, {
  clipboard_image_reader = function()
    return "/tmp/capture.png", "test", "image/png"
  end,
  clipboard_reader = function()
    image_text_reads = image_text_reads + 1
    return "wrong"
  end,
})

local fallback_reads = 0
local pasted_text = rt._debug_edit_keys("ab", 1, { { key = "ctrl-v" } }, false, {
  clipboard_image_reader = function()
    return nil, "clipboard image unavailable"
  end,
  clipboard_reader = function()
    fallback_reads = fallback_reads + 1
    return "TEXT"
  end,
})

local error_reads = 0
local error_fallback = rt._debug_edit_keys("ab", 1, { { key = "ctrl-v" } }, false, {
  clipboard_image_reader = function()
    error("permission denied")
  end,
  clipboard_reader = function()
    error_reads = error_reads + 1
    return "fallback"
  end,
})

local repeated = rt._debug_edit_keys("", 0, { { key = "ctrl-v" }, { key = "ctrl-v" } }, false, {
  clipboard_image_reader = function()
    return "/tmp/image.png"
  end,
})
assert(repeated.input == "/tmp/image.png /tmp/image.png")
local undo = rt._debug_edit_keys("ab", 1, { { key = "ctrl-v" }, { key = "ctrl--" } }, false, {
  clipboard_image_reader = function()
    return "/tmp/screen shot.png"
  end,
})
assert(undo.input == "ab")
local path = TMP .. "/cancelled.png"
assert(psi.file_write(path, "owned capture"))
rt._debug_edit_keys("", 0, { { key = "ctrl-v" } }, false, {
  clipboard_image_reader = function()
    psi.abort_trigger()
    return path
  end,
})
psi.abort_reset()
assert(not psi.file_exists(path), "discarded captures are removed")
local shell = rt._debug_edit_keys("! ", 2, { { key = "ctrl-v" } }, false, {
  clipboard_image_reader = function()
    error("shell drafts must not capture images")
  end,
  clipboard_reader = function()
    return "text"
  end,
})
assert(shell.input == "! text")
return table.concat({
  pasted_image.input,
  tostring(pasted_image.cursor),
  tostring(image_text_reads),
  pasted_text.input,
  tostring(pasted_text.cursor),
  tostring(fallback_reads),
  error_fallback.input,
  tostring(error_fallback.cursor),
  tostring(error_reads),
}, "|")
