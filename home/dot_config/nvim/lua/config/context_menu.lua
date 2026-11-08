-- Filetype-specific commands under <leader>, (the "context" menu).
--
--   require("config.context_menu").add(bufnr, "OpenSCAD", {
--     { "c", open_cheatsheet, "Cheatsheet" },
--   })
--
-- Mappings are buffer-local, and which-key shows the menu under the given
-- name for that buffer only.

local M = {}

M.prefix = "<leader>,"

local function label(bufnr, name)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  pcall(function()
    require("which-key").add({
      { M.prefix, group = name, buffer = bufnr },
    })
  end)
end

function M.add(bufnr, name, entries)
  for _, entry in ipairs(entries) do
    vim.keymap.set("n", M.prefix .. entry[1], entry[2], {
      buffer = bufnr,
      silent = true,
      desc = entry[3],
    })
  end

  -- which-key loads on VeryLazy; do not force it to load early.
  if package.loaded["which-key"] then
    label(bufnr, name)
  else
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      once = true,
      callback = function()
        label(bufnr, name)
      end,
    })
  end
end

return M
