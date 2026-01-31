local M = {}

function M.find_files_from_home()
  require("fzf-lua").files({
    cwd = vim.fn.expand("~"),
    prompt = "Home> ",
  })
end

return M
