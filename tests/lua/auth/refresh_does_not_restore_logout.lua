--[==[psi-test
expect = "ok"
env = { PSI_AUTH_FILE = "{TMP}/auth.json" }
]==]
local storage = require("psi.auth_storage")
local stale = { type = "oauth", access = "old", refresh = "expired", expires = 0 }
assert(storage.set("test", stale))
assert(storage.remove("test"))
local fresh, err = storage.ensure_oauth("test", stale, function(entry)
  return entry and entry.type == "oauth"
end, function()
  error("refresh must not restore the credential after logout")
end)
assert(not fresh and err:find("No compatible saved login", 1, true))
assert(not storage.get("test"))
return "ok"
