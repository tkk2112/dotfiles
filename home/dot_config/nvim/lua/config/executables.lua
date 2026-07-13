local M = {}

function M.find(command, fallbacks)
  local path = vim.fn.exepath(command)
  if path ~= "" then
    return path
  end

  for _, candidate in ipairs(fallbacks or {}) do
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end

  return command
end

return M
