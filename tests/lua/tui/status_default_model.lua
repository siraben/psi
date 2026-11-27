--[==[psi-test
contains = "model:?"
not_contains = "claude-opus"
env = { PSI_PROVIDER = "", PSI_MODEL = "" }
]==]
local tui = require("psi.tui_status")
require("psi.api_registry").provider_has_auth = function()
  return false
end
return tui.status_line(psi.json_encode({ busy = false, scroll = 0 }))
