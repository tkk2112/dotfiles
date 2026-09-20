local M = {}

local transient_filetypes = {
  NvimTree = true,
  fzf = true,
  ["fzf-lua"] = true,
  ["grug-far"] = true,
  help = true,
  lazy = true,
  mason = true,
  oil = true,
  qf = true,
  trouble = true,
}

function M.is_file(bufnr)
  bufnr = bufnr or 0

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  return vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

function M.is_transient(bufnr)
  bufnr = bufnr or 0

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end

  if vim.bo[bufnr].buftype ~= "" then
    return true
  end

  return transient_filetypes[vim.bo[bufnr].filetype] == true
end

function M.is_writable_file(bufnr)
  if not M.is_file(bufnr) then
    return false
  end

  return vim.bo[bufnr].modifiable and not vim.bo[bufnr].readonly
end

return M
