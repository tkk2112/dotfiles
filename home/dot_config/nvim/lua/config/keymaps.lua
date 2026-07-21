local map = vim.keymap.set

local autosave = require("config.autosave")
local format = require("config.format")
local project = require("config.project")
local project_settings = require("config.project_settings")
local search = require("config.search")
local shortcuts = require("config.shortcuts")
local terminal = require("config.terminal")
local theme = require("config.theme")
local tmux_nav = require("config.tmux_nav")

local function map_shortcuts(modes, lhses, rhs, opts)
  for _, lhs in ipairs(lhses) do
    map(modes, lhs, rhs, opts)
  end
end

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

local function close_other_buffers()
  vim.schedule(function()
    local current = vim.api.nvim_get_current_buf()
    local bufremove = require("mini.bufremove")
    local failed = {}

    for _, buffer in
      ipairs(vim.fn.getbufinfo({
        buflisted = 1,
      }))
    do
      local bufnr = buffer.bufnr

      if bufnr ~= current and vim.api.nvim_buf_is_valid(bufnr) then
        local ok, err = pcall(bufremove.delete, bufnr, false)

        if not ok or (vim.api.nvim_buf_is_valid(bufnr) and vim.fn.buflisted(bufnr) == 1) then
          local name = buffer.name ~= "" and vim.fn.fnamemodify(buffer.name, ":~:.") or "[No Name]"

          table.insert(failed, ok and name or name .. ": " .. tostring(err))
        end
      end
    end

    if #failed > 0 then
      vim.notify("Could not close these buffers:\n" .. table.concat(failed, "\n"), vim.log.levels.WARN)
    end
  end)
end

local function cycle_buffer(command)
  return function()
    vim.cmd(command)
  end
end

local function is_jump_noise_buffer(bufnr)
  if vim.bo[bufnr].buftype ~= "" then
    return true
  end

  return vim.tbl_contains({
    "grug-far",
    "help",
    "lazy",
    "mason",
    "oil",
    "qf",
    "trouble",
  }, vim.bo[bufnr].filetype)
end

local function jump_filtered(direction)
  local keys = direction == "back" and "<C-o>" or "<C-i>"

  for _ = 1, 20 do
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "n", false)
    vim.cmd("redraw")

    if not is_jump_noise_buffer(vim.api.nvim_get_current_buf()) then
      return
    end
  end

  vim.notify("No non-plugin jump target found", vim.log.levels.WARN)
end

local restart_session = vim.fn.stdpath("state") .. "/restart-session.vim"

local function save_modified_file_buffers()
  local unsaved = {}

  for _, buffer in
    ipairs(vim.fn.getbufinfo({
      bufloaded = 1,
      bufmodified = 1,
    }))
  do
    local bufnr = buffer.bufnr

    -- Ignore terminal, quickfix, prompt, help, and plugin scratch buffers.
    if vim.bo[bufnr].buftype == "" then
      if buffer.name == "" then
        table.insert(unsaved, {
          bufnr = bufnr,
          name = "[No Name]",
          error = "buffer has no filename",
        })
      else
        local ok, err = pcall(function()
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("silent update")
          end)
        end)

        if not ok or vim.bo[bufnr].modified then
          table.insert(unsaved, {
            bufnr = bufnr,
            name = vim.fn.fnamemodify(buffer.name, ":~:."),
            error = ok and "buffer remains modified" or tostring(err),
          })
        end
      end
    end
  end

  return unsaved
end

local function restart_neovim()
  local unsaved = save_modified_file_buffers()

  if #unsaved > 0 then
    local lines = {
      "Restart cancelled: unsaved file buffers remain:",
    }

    for _, buffer in ipairs(unsaved) do
      table.insert(lines, string.format("%s (buffer %d): %s", buffer.name, buffer.bufnr, buffer.error))
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)

    return
  end

  local session = vim.fn.fnameescape(restart_session)

  vim.cmd("mksession! " .. session)
  vim.cmd("restart source " .. session)
end

local function select_all()
  vim.cmd("normal! ggVG")
end

-- Files and buffers
map("n", "<leader>ww", "<cmd>write<cr>", { desc = "Write current file" })
map("n", "<leader>wa", autosave.save_all, { desc = "Write all modified files" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })
map("n", "<leader>bn", cycle_buffer("BufferLineCycleNext"), { desc = "Next buffer" })
map("n", "<leader>bp", cycle_buffer("BufferLineCyclePrev"), { desc = "Previous buffer" })
map("n", "<leader>bd", close_buffer, { desc = "Close buffer" })
map("n", "<leader>bo", close_other_buffers, {
  desc = "Close other buffers",
})

map_shortcuts({ "n", "i", "x" }, shortcuts.save, "<cmd>write<cr>", { desc = "Write current file" })
map_shortcuts("n", shortcuts.close_buffer, close_buffer, { desc = "Close buffer" })
map_shortcuts("i", shortcuts.close_buffer, from_insert(close_buffer), { desc = "Close buffer" })

map("n", "<C-Tab>", cycle_buffer("BufferLineCycleNext"), { desc = "Next buffer" })
map("i", "<C-Tab>", from_insert(cycle_buffer("BufferLineCycleNext")), { desc = "Next buffer" })
map("n", "<C-S-Tab>", cycle_buffer("BufferLineCyclePrev"), { desc = "Previous buffer" })
map("i", "<C-S-Tab>", from_insert(cycle_buffer("BufferLineCyclePrev")), { desc = "Previous buffer" })

-- Editing
map("n", "<leader>aa", select_all, { desc = "Select all" })
map("x", "<Tab>", ">gv", { desc = "Indent selection" })
map("x", "<S-Tab>", "<gv", { desc = "Outdent selection" })
map("n", "<M-Up>", "<cmd>move .-2<cr>==", { desc = "Move line up" })
map("n", "<M-Down>", "<cmd>move .+1<cr>==", { desc = "Move line down" })
map("x", "<M-Up>", ":move '<-2<cr>gv=gv", { desc = "Move selection up" })
map("x", "<M-Down>", ":move '>+1<cr>gv=gv", { desc = "Move selection down" })

-- Search and pickers
map("n", "<leader>/", search.buffer, { desc = "Search buffer" })
map("n", "<leader>sg", search.project, { desc = "Search project" })
map("n", "<leader>pf", project.find_files, { desc = "Find file in project" })

map_shortcuts("n", shortcuts.search_buffer, search.buffer, { desc = "Search buffer" })
map_shortcuts("i", shortcuts.search_buffer, from_insert(search.buffer), { desc = "Search buffer" })
map_shortcuts("n", shortcuts.search_project, search.project, { desc = "Search project" })
map_shortcuts("i", shortcuts.search_project, from_insert(search.project), { desc = "Search project" })
map_shortcuts("n", shortcuts.project_files, project.find_files, { desc = "Find file in project" })
map_shortcuts("i", shortcuts.project_files, from_insert(project.find_files), { desc = "Find file in project" })
map_shortcuts("n", shortcuts.home_files, search.find_files_from_home, { desc = "Find file from home" })
map_shortcuts("i", shortcuts.home_files, from_insert(search.find_files_from_home), { desc = "Find file from home" })

-- Projects
map("n", "<leader>pp", project.pick, { desc = "Pick project" })
map("n", "<leader>pa", project.add_current, { desc = "Add current directory as project" })
map("n", "<leader>pA", project.add_path, { desc = "Add project by path" })
map("n", "<leader>pc", project.print_root, { desc = "Print project root" })
map("n", "<leader>pg", project.live_grep, { desc = "Grep project" })
map("n", "<leader>pr", project_settings.reload, { desc = "Reload project settings" })
map("n", "<leader>ps", project_settings.print, { desc = "Print project settings" })
map("n", "<leader>pS", project.edit_config, { desc = "Edit project settings" })

-- Navigation
map("n", "<M-Left>", function()
  jump_filtered("back")
end, { desc = "Jump back" })

map("n", "<M-Right>", function()
  jump_filtered("forward")
end, { desc = "Jump forward" })

map("n", "<C-Left>", "b", { desc = "Word left" })
map("n", "<C-Right>", "w", { desc = "Word right" })
map("i", "<C-Left>", "<C-o>b", { desc = "Word left" })
map("i", "<C-Right>", "<C-o>w", { desc = "Word right" })
map("n", "<PageUp>", "<C-u>", { desc = "Scroll half page up" })
map("n", "<PageDown>", "<C-d>", { desc = "Scroll half page down" })

-- tmux integration
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

-- Terminal
map("n", "<C-`>", terminal.toggle, { desc = "Toggle terminal" })
map("t", "<C-`>", terminal.toggle, { desc = "Toggle terminal" })
map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Configuration and UI
map("n", "<leader>rr", restart_neovim, {
  desc = "Restart Neovim and reload config",
})
map("n", "<leader>rs", "<cmd>Lazy sync<cr>", { desc = "Sync lazy.nvim plugins" })
map("n", "<leader>lf", function()
  format.format(0)
end, { desc = "Format buffer" })
map("n", "<leader>ut", theme.toggle, { desc = "Toggle theme" })
map("n", "<leader>te", "<cmd>ThemeEdit<cr>", { desc = "Edit colorscheme" })
map("n", "<leader>tr", "<cmd>ThemeReload<cr>", { desc = "Reload colorscheme" })
map("n", "<leader>ta", "<cmd>ThemeApply<cr>", { desc = "Apply and reload colorscheme" })
map("n", "<F24>", function()
  vim.show_pos()
end, { desc = "Inspect highlights under cursor" })
