local M = {}

local project = require("config.project")

function M.buffer()
  require("fzf-lua").blines()
end

function M.project()
  require("grug-far").open({
    prefills = {
      paths = project.current_root(),
    },
  })
end

return M
