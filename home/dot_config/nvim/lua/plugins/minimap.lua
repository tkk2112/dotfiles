return {
  {
    "wfxr/minimap.vim",
    cmd = {
      "Minimap",
      "MinimapToggle",
      "MinimapClose",
      "MinimapRefresh",
      "MinimapUpdateHighlight",
    },
    init = function()
      vim.g.minimap_width = 10
      vim.g.minimap_auto_start = 0
      vim.g.minimap_auto_start_win_enter = 0
      vim.g.minimap_highlight_range = 1
      vim.g.minimap_highlight_search = 1
      vim.g.minimap_git_colors = 0
    end,
    keys = {
      {
        "<leader>um",
        "<cmd>MinimapToggle<cr>",
        desc = "Toggle minimap",
      },
    },
  },
}
