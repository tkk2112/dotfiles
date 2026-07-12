local map = vim.keymap.set

local autosave = require("config.autosave")
local format = require("config.format")
local pickers = require("config.pickers")
local project = require("config.project")
local project_settings = require("config.project_settings")
local terminal = require("config.terminal")
local theme = require("config.theme")
local tmux_nav = require("config.tmux_nav")
local search = require("config.search")

local is_macos = vim.uv.os_uname().sysname == "Darwin"

local function from_insert(callback)
  return function()
    vim.cmd("stopinsert")
    vim.schedule(callback)
  end
end

local function map_tmux_nav(mode, lhs, direction)
  map(mode, lhs, function()
    tmux_nav.move(direction)
  end, { desc = "Navigate " .. direction })
end

local function close_buffer()
  vim.schedule(function()
    local bufnr = vim.api.nvim_get_current_buf()

    if not vim.api.nvim_buf_is_valid(bufnr) then
      vim.notify("Current buffer is not valid", vim.log.levels.WARN)
      return
    end

    require("mini.bufremove").delete(bufnr, false)
  end)
end

local function is_jump_noise_buffer(bufnr)
  local buftype = vim.bo[bufnr].buftype
  local filetype = vim.bo[bufnr].filetype

  if buftype ~= "" then
    return true
  end

  return vim.tbl_contains({
    "grug-far",
    "oil",
    "qf",
    "help",
    "lazy",
    "mason",
    "trouble",
  }, filetype)
end

local function jump_filtered(direction)
  local keys = direction == "back" and "<C-o>" or "<C-i>"

  for _ = 1, 20 do
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(keys, true, false, true),
      "n",
      false
    )

    vim.cmd("redraw")

    local bufnr = vim.api.nvim_get_current_buf()
    if not is_jump_noise_buffer(bufnr) then
      return
    end
  end

  vim.notify("No non-plugin jump target found", vim.log.levels.WARN)
end

local function select_all()
  vim.cmd("normal! ggVG")
end

-- Basic actions
map("n", "<leader>ww", "<cmd>write<cr>", { desc = "Write current file" })
map("n", "<leader>wa", autosave.save_all, { desc = "Write all modified files" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })

map({ "n", "i" }, "<C-s>", "<cmd>write<cr>", { desc = "Write current file" })
if is_macos then
  map({ "n", "i" }, "<D-s>", "<cmd>write<cr>", { desc = "Write current file" })
end

map("n", "<leader>aa", select_all, { desc = "Select all" })
map("i", "<leader>aa", function()
  vim.cmd("stopinsert")
  select_all()
end, { desc = "Select all" })

-- Close buffer
map("n", "<C-w>", close_buffer, { desc = "Close buffer" })
map("i", "<C-w>", from_insert(close_buffer), { desc = "Close buffer" })
if is_macos then
  map("n", "<D-w>", close_buffer, { desc = "Close buffer" })
  map("i", "<D-w>", from_insert(close_buffer), { desc = "Close buffer" })
end

map("n", "<leader>bd", close_buffer, { desc = "Close buffer" })

-- Search
map("n", "<C-F>", search.buffer, { desc = "Search buffer" })
map("i", "<C-F>", from_insert(search.buffer), { desc = "Search buffer" })

map("n", "<C-S-F>", search.project, { desc = "Search project" })
map("i", "<C-S-F>", from_insert(search.project), { desc = "Search project" })
if is_macos then
  map("n", "<D-f>", search.buffer, { desc = "Search buffer" })
  map("i", "<D-f>", from_insert(search.buffer), { desc = "Search buffer" })

  map("n", "<D-F>", search.project, { desc = "Search project" })
  map("i", "<D-F>", from_insert(search.project), { desc = "Search project" })
end

map("n", "<leader>/", search.buffer, { desc = "Search buffer" })
map("n", "<leader>sg", search.project, { desc = "Search project" })

-- Reload config/plugins
map("n", "<leader>rr", function()
  for name, _ in pairs(package.loaded) do
    if name:match("^config") or name:match("^plugins") then
      package.loaded[name] = nil
    end
  end

  dofile(vim.env.MYVIMRC)
  vim.notify("Reloaded Neovim config", vim.log.levels.INFO)
end, { desc = "Reload Neovim config" })

map("n", "<leader>rs", "<cmd>Lazy sync<cr>", { desc = "Sync lazy.nvim plugins" })

-- Terminal
map("n", "<C-`>", terminal.toggle, { desc = "Toggle terminal" })
map("t", "<C-`>", terminal.toggle, { desc = "Toggle terminal" })
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- tmux-aware navigation. tmux must forward Ctrl-a Arrow/v/s/x into Neovim.
map_tmux_nav("n", "<C-a><Left>", "left")
map_tmux_nav("n", "<C-a><Down>", "down")
map_tmux_nav("n", "<C-a><Up>", "up")
map_tmux_nav("n", "<C-a><Right>", "right")

map_tmux_nav("t", "<C-a><Left>", "left")
map_tmux_nav("t", "<C-a><Down>", "down")
map_tmux_nav("t", "<C-a><Up>", "up")
map_tmux_nav("t", "<C-a><Right>", "right")

map("n", "<C-a>s", "<cmd>split<cr>", { desc = "Horizontal split" })
map("n", "<C-a>v", "<cmd>vsplit<cr>", { desc = "Vertical split" })

map("t", "<C-a>s", [[<C-\><C-n><cmd>split<cr>]], { desc = "Horizontal split" })
map("t", "<C-a>v", [[<C-\><C-n><cmd>vsplit<cr>]], { desc = "Vertical split" })

map("n", "<C-a>x", tmux_nav.close_window, { desc = "Close window" })
map("t", "<C-a>x", tmux_nav.close_window, { desc = "Close window" })

-- Project/file pickers
map("n", "<leader>pf", project.find_files, { desc = "Find file in project" })

map("n", "<C-p>", project.find_files, { desc = "Find file in project" })
map("i", "<C-p>", from_insert(project.find_files), { desc = "Find file in project" })
map("n", "<C-o>", pickers.find_files_from_home, { desc = "Find file from home" })
map("i", "<C-o>", from_insert(pickers.find_files_from_home), { desc = "Find file from home" })
if is_macos then
  map("n", "<D-p>", project.find_files, { desc = "Find file in project" })
  map("i", "<D-p>", from_insert(project.find_files), { desc = "Find file in project" })
  map("n", "<D-o>", pickers.find_files_from_home, { desc = "Find file from home" })
  map("i", "<D-o>", from_insert(pickers.find_files_from_home), { desc = "Find file from home" })
end

-- Project actions
map("n", "<leader>pp", project.pick, { desc = "Pick project" })
map("n", "<leader>pa", project.add_current, { desc = "Add current directory as project" })
map("n", "<leader>pA", project.add_path, { desc = "Add project by path" })
map("n", "<leader>pg", project.live_grep, { desc = "Grep project" })
map("n", "<leader>pc", project.print_root, { desc = "Print project root" })
map("n", "<leader>pr", project_settings.reload, { desc = "Reload project settings" })
map("n", "<leader>ps", project_settings.print, { desc = "Print project settings" })
map("n", "<leader>pS", project.edit_config, { desc = "Edit project settings" })

-- Buffer tabs
map("n", "<leader>bn", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous buffer" })
map("n", "<leader>bd", close_buffer, { desc = "Close buffer" })

-- Ghostty sends these for Ctrl-Tab / Ctrl-Shift-Tab.
map("n", "\27[27;5;9~", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
map("n", "\27[27;6;9~", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous buffer" })

map("i", "\27[27;5;9~", from_insert(function()
  vim.cmd("BufferLineCycleNext")
end), { desc = "Next buffer" })

map("i", "\27[27;6;9~", from_insert(function()
  vim.cmd("BufferLineCyclePrev")
end), { desc = "Previous buffer" })

-- Jump history
map("n", "<M-Left>", function()
  jump_filtered("back")
end, { desc = "Jump back" })

map("n", "<M-Right>", function()
  jump_filtered("forward")
end, { desc = "Jump forward" })

-- Word movement. Do not map terminal mode; shell handles it there.
map("n", "<C-Left>", "b", { desc = "Word left" })
map("n", "<C-Right>", "w", { desc = "Word right" })

map("i", "<C-Left>", "<C-o>b", { desc = "Word left" })
map("i", "<C-Right>", "<C-o>w", { desc = "Word right" })

-- Language/UI
map("n", "<leader>lf", function()
  format.format(0)
end, { desc = "Format buffer" })

map("n", "<leader>ut", theme.toggle, { desc = "Toggle theme" })

-- macOS Fn-Up/Fn-Down usually arrive as PageUp/PageDown.
map("n", "<PageUp>", "<C-u>", { desc = "Scroll half page up" })
map("n", "<PageDown>", "<C-d>", { desc = "Scroll half page down" })

vim.keymap.set("n", "<F24>", function()
  vim.show_pos()
end, {
  desc = "Inspect highlights under cursor",
})

vim.keymap.set("n", "<leader>te", "<cmd>ThemeEdit<cr>", {
  desc = "Edit colorscheme",
})

vim.keymap.set("n", "<leader>tr", "<cmd>ThemeReload<cr>", {
  desc = "Reload colorscheme",
})

vim.keymap.set("n", "<leader>ta", "<cmd>ThemeApply<cr>", {
  desc = "Apply and reload colorscheme",
})
