--[==[psi-test
expect = "ok"
cwd = "protected-extensions"
files = [
  { path = ".psi/extensions/01-load-error.lua", text = "error('file load failure', 0)" },
  { path = ".psi/extensions/02-init-error.lua", text = "return function() error('file init failure', 0) end" },
  { path = ".psi/extensions/03-value.lua", text = "psi._extension_order = (psi._extension_order or '') .. 'value,'; return 42" },
  { path = ".psi/extensions/04-init.lua", text = "return function(p) p._extension_order = p._extension_order .. 'init,' end" },
]
]==]
local notices = {}
psi.notice.error = function(text, opts)
  assert(opts.source == "extension-loader")
  notices[#notices + 1] = text
end
local original_require = require
local acquired = 0
local scenario = "load"
_G.require = function(name)
  if name ~= "psi.extensions.btw" then
    return original_require(name)
  end
  acquired = acquired + 1
  if scenario == "load" then
    error("package load failure", 0)
  end
  if scenario == "init" then
    return function()
      error("package init failure", 0)
    end
  end
  if scenario == "value" then
    return 42
  end
  return function(p)
    p._packaged_init = (p._packaged_init or 0) + 1
  end
end
psi.load_user_extensions = false
for _, value in ipairs({ "load", "init", "value", "ok" }) do
  scenario = value
  dofile(ROOT .. "/lua/boot.lua")
end
assert(acquired == 4 and psi._packaged_init == 1)
assert(#notices == 2)
assert(
  notices[1] == "psi: packaged extension psi.extensions.btw failed to load: package load failure"
)
assert(
  notices[2]
    == "psi: packaged extension psi.extensions.btw failed during init: package init failure"
)
_G.require = original_require
psi._extension_order = ""
psi.load_extensions()
assert(psi._extension_order == "value,init,")
assert(#notices == 4)
assert(notices[3]:find("01-load-error.lua failed to load: file load failure", 1, true))
assert(notices[4]:find("02-init-error.lua failed during init: file init failure", 1, true))
psi.load_extensions()
assert(psi._extension_order == "value,init,value,init,", "filesystem extensions reload with dofile")
psi.project_trusted = false
psi.load_extensions()
assert(psi._extension_order == "value,init,value,init,")
return "ok"
