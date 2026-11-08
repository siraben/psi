--[==[psi-test
expect = "ok"
]==]
local resources = require("psi.resource_loader")
local getenv = os.getenv
for _, env in ipairs({
  { HOME = "/home", XDG_CONFIG_HOME = "/xdg", root = "/xdg/psi" },
  { HOME = "/home", XDG_CONFIG_HOME = "", root = "/home/.config/psi" },
  { HOME = "", XDG_CONFIG_HOME = "/xdg", root = "/xdg/psi" },
  { HOME = "", XDG_CONFIG_HOME = "" },
  {},
}) do
  os.getenv = function(key)
    return env[key]
  end
  assert(require("psi.config_paths").config_dir() == env.root)
  assert(
    require("psi.settings_manager").global_path()
      == (env.root and env.root .. "/settings.json" or nil)
  )
  psi.cwd = function()
    return "/project"
  end
  for _, trusted in ipairs({ false, true }) do
    psi.project_trusted = trusted
    for _, project_present in ipairs({ false, true }) do
      for _, global_present in ipairs({ false, true }) do
        for _, item in ipairs({
          { "SYSTEM.md", resources.system_prompt_file },
          { "APPEND_SYSTEM.md", resources.append_system_prompt_file },
        }) do
          local project = "/project/.psi/" .. item[1]
          local global = env.root and env.root .. "/" .. item[1]
          local visited = {}
          psi.file_exists = function(path)
            visited[#visited + 1] = path
            return (path == project and project_present) or (path == global and global_present)
          end
          psi.read_file = function(path)
            return "content:" .. path
          end
          local path, content = item[2]()
          local expected = trusted and project_present and project
            or global_present and global
            or nil
          assert(path == expected)
          assert(content == (expected and "content:" .. expected or nil))
          if not trusted then
            for _, checked in ipairs(visited) do
              assert(checked ~= project)
            end
          end
        end
      end
    end
  end
end
os.getenv = getenv
return "ok"
