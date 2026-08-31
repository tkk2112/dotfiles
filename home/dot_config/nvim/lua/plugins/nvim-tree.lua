local function project_root()
  return require("config.project").scope_root()
end

local function toggle_tree()
  require("nvim-tree.api").tree.toggle({
    path = project_root(),
    find_file = true,
    update_root = true,
    focus = true,
  })
end

local function on_attach(bufnr)
  local api = require("nvim-tree.api")

  local function opts(desc)
    return {
      buffer = bufnr,
      desc = "File tree: " .. desc,
      noremap = true,
      silent = true,
      nowait = true,
    }
  end

  api.map.on_attach.default(bufnr)

  vim.keymap.set("n", "s", function()
    require("flash").jump()
  end, opts("Flash jump"))

  vim.keymap.set("n", "l", api.node.open.edit, opts("Open"))
  vim.keymap.set("n", "h", api.node.navigate.parent_close, opts("Collapse"))
end

return {
  {
    "nvim-tree/nvim-tree.lua",
    init = function()
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1
    end,
    opts = {
      on_attach = on_attach,

      view = {
        width = 36,
        side = "left",
      },

      renderer = {
        indent_markers = {
          enable = true,
        },
      },

      filters = {
        dotfiles = false,
        git_ignored = false,
      },

      git = {
        enable = true,
      },

      diagnostics = {
        enable = true,
        show_on_dirs = true,
      },

      update_focused_file = {
        enable = true,
        update_root = false,
      },
    },
    keys = {
      {
        "<leader>e",
        toggle_tree,
        desc = "Toggle project tree",
      },
    },
  },
}
