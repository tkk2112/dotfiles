local M = {}

function M.is_file(bufnr)
  bufnr = bufnr or 0

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  return vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

function M.is_writable_file(bufnr)
  if not M.is_file(bufnr) then
    return false
  end

  return vim.bo[bufnr].modifiable and not vim.bo[bufnr].readonly
end

return M
