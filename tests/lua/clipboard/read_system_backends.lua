--[==[psi-test
expect = "wayland|wl-paste|wl-paste|true|wl-paste|x11|xsel|wl-paste,xclip,xsel|mac|pbpaste|win|powershell|true"
]==]
local clipboard = require("psi.clipboard")

local function run(env, is_windows, results)
  local calls = {}
  local text, backend, err = clipboard.read_system({
    env = env,
    is_windows = is_windows,
    run_argv = function(argv)
      local name = argv[1]
      calls[#calls + 1] = name
      return results[name] or { status = 1, output = "" }
    end,
  })
  return text, backend, err, table.concat(calls, ",")
end

local way_text, way_backend, _, way_calls = run(
  { WAYLAND_DISPLAY = "wayland-0", DISPLAY = ":0" },
  false,
  { ["wl-paste"] = { status = 0, output = "wayland" } }
)

-- An empty but successful Wayland read must not fall back to stale X11 text.
local empty_text, empty_backend, _, empty_calls = run(
  { WAYLAND_DISPLAY = "wayland-0", DISPLAY = ":0" },
  false,
  {
    ["wl-paste"] = { status = 0, output = "" },
    xclip = { status = 0, output = "stale" },
  }
)

local x_text, x_backend, _, x_calls = run(
  { WAYLAND_DISPLAY = "wayland-0", DISPLAY = ":0" },
  false,
  {
    ["wl-paste"] = { status = 1, output = "" },
    xclip = { status = 1, output = "" },
    xsel = { status = 0, output = "x11" },
  }
)

local mac_text, mac_backend = run({}, false, { pbpaste = { status = 0, output = "mac" } })
local win_text, win_backend = run({}, true, { ["powershell.exe"] = { status = 0, output = "win" } })

local large_text, _, large_err = run(
  { DISPLAY = ":0" },
  false,
  { xclip = { status = 0, output = "partial", truncated = true } }
)

if not require("psi.platform").is_windows() then
  local path = TMP .. "/clipboard-reader"
  assert(psi.file_write(path, "#!/bin/sh\nprintf 'clipboard text'\nprintf 'diagnostic' >&2\n"))
  assert(psi.file_chmod(path, 448))
  local begin = psi.process_begin_argv
  psi.process_begin_argv = function(argv)
    assert(argv[1] == "sh" and argv[4] == "psi-clipboard")
    local copy = {}
    for i, arg in ipairs(argv) do
      copy[i] = arg
    end
    copy[5] = path
    return begin(copy)
  end
  local captured = clipboard.read_system({ env = {}, is_windows = false, timeout_ms = 2000 })
  assert(captured == "clipboard text", "stderr is not clipboard data")
  assert(psi.file_write(path, "#!/bin/sh\nexec 1>&- 2>&-\n/bin/sleep 5\n"))
  local started = psi.time_ms()
  local timed_out = clipboard.read_system({ env = {}, is_windows = false, timeout_ms = 100 })
  psi.process_begin_argv = begin
  assert(timed_out == nil and psi.time_ms() - started < 2500, "reader deadline covers early EOF")
end
return table.concat({
  way_text,
  way_backend,
  way_calls,
  tostring(empty_text == nil and empty_calls == "wl-paste"),
  empty_backend,
  x_text,
  x_backend,
  x_calls,
  mac_text,
  mac_backend,
  win_text,
  win_backend,
  tostring(large_text == nil and large_err == "clipboard text too large"),
}, "|")
