-- Supplement older Neovim Zig compiler plugins that do not define
-- an errorformat.

if vim.bo.errorformat == "" then
  vim.opt_local.errorformat = {
    "%E%f:%l:%c: error: %m",
    "%W%f:%l:%c: warning: %m",
    "%I%f:%l:%c: note: %m",
    "%-G%.%#",
  }
end
