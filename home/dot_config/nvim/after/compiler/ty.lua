if vim.g.current_compiler then
  return
end

vim.g.current_compiler = "ty"

vim.opt_local.errorformat = {
  "%E%f:%l:%c: error%m",
  "%W%f:%l:%c: warning%m",
  "%-G%.%#",
}
