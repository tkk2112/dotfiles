vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- UI
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.wrap = false
vim.opt.termguicolors = true

-- Tabs/indentation
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Undo/recovery
vim.opt.undofile = true
vim.opt.undolevels = 10000
vim.opt.undoreload = 10000
vim.opt.swapfile = true
vim.opt.backup = false
vim.opt.writebackup = true

-- File reload/write behavior
vim.opt.autoread = true
vim.opt.confirm = true
vim.opt.updatetime = 300

-- Command-line completion
vim.opt.wildmenu = true
vim.opt.wildmode = "longest:full,full"
vim.opt.wildoptions = "pum"

-- Completion menu behavior
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.shortmess:append("c")

-- Splits
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Key timing
vim.opt.timeout = true
vim.opt.timeoutlen = 500
vim.opt.ttimeout = true
vim.opt.ttimeoutlen = 50

-- Provider integrations are disabled intentionally; current config is Lua-native.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  command = "checktime",
})

vim.opt.guicursor = {
  "n-v-c-sm:block-Cursor",
  "i-ci-ve:block-CursorInsert",
  "r-cr:block-CursorReplace",
  "o:block-Cursor",
}
