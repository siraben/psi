-- Global configuration only: credentials, extensions and keybindings retain
-- their HOME-only policy; sessions use XDG_STATE_HOME.
local prelude = require("psi.prelude")

local M = {}

function M.config_dir()
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then
    return prelude.path_join(xdg, "psi")
  end
  local home = os.getenv("HOME")
  if home and home ~= "" then
    return prelude.path_join(home, ".config/psi")
  end
  return nil
end

return M
