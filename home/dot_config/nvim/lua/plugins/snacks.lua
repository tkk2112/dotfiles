return {
  {
    -- Only the image viewer is used (OpenSCAD snapshots); it renders PNGs with
    -- the kitty graphics protocol in Ghostty, kitty and WezTerm, also in tmux.
    "folke/snacks.nvim",
    -- snacks registers its image handlers during setup, so load it at startup.
    lazy = false,
    opts = {
      image = {
        enabled = true,
      },
    },
  },
}
