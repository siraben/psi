--[==[psi-test
expect = "true|true|true|true|true|true"
]==]
local t = require("psi.tools")
local all = #t.select_specs()
t.set_active({"read", "grep"})
local narrowed = #t.select_specs()
local inactive = t.dispatch("bash", { command = "printf nope" })
local active = t.get_active()
local has_read, has_grep = false, false
for _, name in ipairs(active) do
  if name == "read" then has_read = true end
  if name == "grep" then has_grep = true end
end
t.set_active(nil)
local restored = #t.select_specs()
return tostring(all >= 3) .. "|" .. tostring(narrowed == 2) .. "|"
  .. tostring(has_read) .. "|" .. tostring(has_grep) .. "|" .. tostring(all == restored)
  .. "|" .. tostring(inactive.ok == false and inactive.error == "Tool bash not found")
