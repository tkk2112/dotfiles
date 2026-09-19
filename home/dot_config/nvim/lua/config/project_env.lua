-- config/project_env.lua

local M = {}

-- direnv evaluates .envrc in a shell subprocess. Any side effects performed
-- while evaluating it still happen (for example bootstrapping a venv,
-- installing tools, creating files, or updating caches), but only the exported
-- environment is returned to Neovim by `direnv export json`.
--
-- Comes back to Neovim:              Does not come back:
--   PATH                               aliases
--   VIRTUAL_ENV                        shell functions
--   IDF_PATH                           shell options
--   CC / CXX                           cd performed inside .envrc
--   other exported variables           non-exported/local shell variables
--
-- Consequently, executables made available through PATH work normally from
-- project commands, terminals, LSPs, etc. Shell aliases/functions defined by
-- an .envrc or something it sources do not; those need to be real executable
-- scripts if Neovim must invoke them.
local function apply_direnv(cwd)
  local result = vim
    .system({
      "direnv",
      "export",
      "json",
    }, {
      cwd = cwd,
      text = true,
    })
    :wait()

  if result.code ~= 0 then
    vim.notify("direnv failed for " .. cwd .. ":\n" .. vim.trim(result.stderr or ""), vim.log.levels.WARN)

    return false
  end

  local output = vim.trim(result.stdout or "")

  if output == "" then
    return true
  end

  local ok, environment = pcall(vim.json.decode, output)

  if not ok or type(environment) ~= "table" then
    vim.notify("Could not decode direnv environment for " .. cwd, vim.log.levels.ERROR)
    return false
  end

  for name, value in pairs(environment) do
    if value == vim.NIL then
      vim.env[name] = nil
    else
      vim.env[name] = tostring(value)
    end
  end

  return true
end

function M.update(cwd)
  if vim.fn.executable("direnv") ~= 1 then
    return true
  end

  cwd = cwd or vim.fn.getcwd()

  return apply_direnv(cwd)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("dotfiles_project_direnv", {
    clear = true,
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      M.update(vim.fn.getcwd())
    end,
  })

  M.update(vim.fn.getcwd())
end

return M
