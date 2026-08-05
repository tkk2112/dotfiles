return {
  {
    "lewis6991/gitsigns.nvim",
    event = "VeryLazy",
    opts = {
      current_line_blame = true,

      current_line_blame_opts = {
        virt_text_pos = "eol",
        delay = 500,
      },

      current_line_blame_formatter = function(_, blame_info)
        local bufnr = vim.api.nvim_get_current_buf()
        local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

        if #vim.diagnostic.get(bufnr, { lnum = lnum }) > 0 then
          return {}
        end

        local sha = blame_info.abbrev_sha:sub(1, 7)
        local date = os.date("%Y-%m-%d", blame_info.author_time)

        return {
          {
            string.format("  %s %s, %s - %s", sha, blame_info.author, date, blame_info.summary),
            "GitSignsCurrentLineBlame",
          },
        }
      end,

      current_line_blame_formatter_nc = function()
        local bufnr = vim.api.nvim_get_current_buf()
        local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

        if #vim.diagnostic.get(bufnr, { lnum = lnum }) > 0 then
          return {}
        end

        return {
          {
            "  Not committed yet",
            "GitSignsCurrentLineBlame",
          },
        }
      end,

      on_attach = function(bufnr)
        local gitsigns = require("gitsigns")
        local map = vim.keymap.set

        local options = {
          buffer = bufnr,
          silent = true,
        }

        local function with_desc(description)
          return vim.tbl_extend("force", options, {
            desc = description,
          })
        end

        map("n", "<leader>gb", gitsigns.blame_line, with_desc("Blame line"))

        map("n", "<leader>gB", gitsigns.toggle_current_line_blame, with_desc("Toggle current line blame"))

        map("n", "<leader>gp", gitsigns.preview_hunk, with_desc("Preview hunk"))

        map("n", "]c", function()
          if vim.wo.diff then
            vim.cmd("normal! ]c")
            return
          end

          gitsigns.nav_hunk("next")
        end, with_desc("Next hunk"))

        map("n", "[c", function()
          if vim.wo.diff then
            vim.cmd("normal! [c")
            return
          end

          gitsigns.nav_hunk("prev")
        end, with_desc("Previous hunk"))
      end,
    },
  },
}
