return {
  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    config = function()
      require("grug-far").setup({
        prefills = { search = vim.fn.expand("<cword>") },
        transient = true,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "grug-far",
        callback = function(event)
          vim.keymap.set("n", "q", "<cmd>close<cr>", {
            buffer = event.buf,
            silent = true,
            desc = "Close Grug FAR",
          })

          vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", {
            buffer = event.buf,
            silent = true,
            desc = "Close Grug FAR",
          })
        end,
      })
    end,
  },
}
