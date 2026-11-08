--[==[psi-test
expect = "ok"
]==]
local loads, lookups = 0, {}
package.loaded["psi.api_registry"] = nil
package.loaded["psi.provider_capabilities"] = nil
package.preload["psi.api_registry"] = function()
  loads = loads + 1
  return {
    model = function(id)
      lookups[#lookups + 1] = id
      if id == "fixture/vendor/vision" then
        return { input = { "image", "text" } }
      end
      if id == "fixture/text" then
        return { input = { "text" } }
      end
      if id == "fixture/empty" then
        return { input = {} }
      end
      if id == "fixture/incomplete" then
        return {}
      end
    end,
  }
end
local capabilities = require("psi.provider_capabilities")
assert(loads == 0)
assert(capabilities.supports_images("fixture", "") == nil and loads == 0)
assert(capabilities.supports_images("fixture", "vendor/vision") == true)
assert(capabilities.supports_images("fixture", "fixture/vendor/vision") == true)
assert(capabilities.supports_images(nil, "fixture/vendor/vision") == true)
assert(capabilities.supports_images("fixture", "text") == false)
assert(capabilities.supports_images("fixture", "empty") == false)
assert(capabilities.supports_images("fixture", "incomplete") == nil)
assert(capabilities.supports_images("fixture", "missing") == nil)
assert(loads == 1 and lookups[1] == lookups[2] and lookups[2] == lookups[3])
package.loaded["psi.api_registry"] = nil
package.preload["psi.api_registry"] = function()
  error("registry unavailable")
end
assert(capabilities.supports_images("fixture", "vendor/vision") == nil)
return "ok"
