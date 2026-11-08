-- Neovide passes GUI keys (<D-…>, <S-BS>, Option combinations) straight to
-- Neovim. In Ghostty and other terminals the same keys are translated before
-- Neovim sees them (see dot_config/ghostty/config.tmpl), so mirror those
-- translations here. Nothing is mapped outside Neovide.

local M = {}

local function map(modes, lhs, rhs, desc)
  vim.keymap.set(modes, lhs, rhs, {
    silent = true,
    desc = desc,
  })
end

-- Same as a terminal's bracketed paste: insert at the cursor in any mode,
-- including terminal buffers and the command line.
local function paste_clipboard()
  vim.paste(vim.fn.getreg("+", 1, true), -1)
end

local function scale_by(factor)
  return function()
    vim.g.neovide_scale_factor = (vim.g.neovide_scale_factor or 1.0) * factor
  end
end

local function reset_scale()
  vim.g.neovide_scale_factor = 1.0
end

function M.setup()
  if not vim.g.neovide then
    return
  end

  -- Started from the Dock or a launcher, Neovim begins in "/", where file
  -- pickers would scan the whole disk. Start in the home directory instead.
  if vim.fn.argc() == 0 and vim.fn.getcwd() == "/" then
    vim.api.nvim_set_current_dir(vim.uv.os_homedir())
  end

  -- Terminals deliver Option combinations as Meta (<M-Up> moves lines,
  -- <M-Left> jumps back). Keep the right Option key for special characters.
  vim.g.neovide_input_macos_option_key_is_meta = "only_left"

  -- Ghostty uses this font; Neovide otherwise falls back to one without icons.
  if vim.o.guifont == "" then
    vim.o.guifont = "FiraCode Nerd Font:h12"
  end

  -- Ghostty: super+left/right send Home/End.
  map({ "n", "x", "o", "i", "c", "t" }, "<D-Left>", "<Home>", "Line start")
  map({ "n", "x", "o", "i", "c", "t" }, "<D-Right>", "<End>", "Line end")

  -- Ghostty: shift+backspace sends a plain backspace.
  map({ "i", "c", "t" }, "<S-BS>", "<BS>", "Backspace")

  -- Shifted letters may arrive as <D-S-f> instead of <D-F>; reuse the
  -- <D-F> shortcut either way.
  vim.keymap.set({ "n", "i" }, "<D-S-f>", "<D-F>", {
    remap = true,
    desc = "Search project",
  })

  -- Ghostty handles copy and paste itself.
  map("x", "<D-c>", '"+y', "Copy to clipboard")
  map({ "n", "x", "i", "c", "t" }, "<D-v>", paste_clipboard, "Paste from clipboard")

  -- Ghostty: super/ctrl +, -, 0 change the font size.
  for _, modifier in ipairs({ "D", "C" }) do
    map({ "n", "x", "i", "t" }, "<" .. modifier .. "-=>", scale_by(1.1), "Increase font size")
    map({ "n", "x", "i", "t" }, "<" .. modifier .. "-+>", scale_by(1.1), "Increase font size")
    map({ "n", "x", "i", "t" }, "<" .. modifier .. "-->", scale_by(1 / 1.1), "Decrease font size")
    map({ "n", "x", "i", "t" }, "<" .. modifier .. "-0>", reset_scale, "Reset font size")
  end
end

return M
