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

function M.find_files_from_home()
  require("fzf-lua").files({
    cwd = vim.fn.expand("~"),
    prompt = "Home> ",
  })
end

return M
