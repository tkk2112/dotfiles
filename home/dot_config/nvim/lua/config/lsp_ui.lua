local float = require("config.ui.float")

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "rounded",
    source = true,
  },
})

local function focus_float(open_float)
  local before = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    before[win] = true
  end

  open_float()

  vim.schedule(function()
    local candidate = nil

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)

      if config.relative ~= "" then
        if not before[win] then
          candidate = win
          break
        end

        candidate = win
      end
    end

    if not candidate or not vim.api.nvim_win_is_valid(candidate) then
      return
    end

    vim.api.nvim_set_current_win(candidate)

    vim.keymap.set("n", "q", "<cmd>close<cr>", {
      buffer = vim.api.nvim_win_get_buf(candidate),
      silent = true,
      desc = "Close floating window",
    })
  end)
end

vim.keymap.set("n", "<Esc>", function()
  if float.close_all() then
    return
  end

  vim.cmd("nohlsearch")
end, {
  silent = true,
  desc = "Close floats / clear search",
})

local group = vim.api.nvim_create_augroup("lsp_keymaps", { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(event)
    local map = vim.keymap.set
    local opts = { buffer = event.buf }

    local function with_desc(desc)
      return vim.tbl_extend("force", opts, { desc = desc })
    end

    map("n", "gd", vim.lsp.buf.definition, with_desc("Goto definition"))
    map("n", "gD", vim.lsp.buf.declaration, with_desc("Goto declaration"))
    map("n", "gr", vim.lsp.buf.references, with_desc("Goto references"))
    map("n", "gi", vim.lsp.buf.implementation, with_desc("Goto implementation"))

    map("n", "<leader>lr", vim.lsp.buf.rename, with_desc("Rename symbol"))
    map("n", "<leader>la", vim.lsp.buf.code_action, with_desc("Code action"))

    -- Hover floats do not reliably accept focus; Esc closes them via close_floats().
    map("n", "<F1>", function()
      if vim.bo.buftype == "help" then
        vim.cmd("close")
        return
      end

      local current_win = vim.api.nvim_get_current_win()
      local current_config = vim.api.nvim_win_get_config(current_win)

      if current_config.relative ~= "" then
        vim.cmd("close")
        return
      end

      local params = vim.lsp.util.make_position_params(0, "utf-8")

      vim.lsp.buf_request(0, "textDocument/hover", params, function(err, result)
        if err or not result or not result.contents then
          return
        end

        local markdown_lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
        markdown_lines = vim.split(table.concat(markdown_lines, "\n"), "\n", {
          trimempty = true,
        })

        if vim.tbl_isempty(markdown_lines) then
          return
        end

        local _, win = vim.lsp.util.open_floating_preview(markdown_lines, "markdown", {
          border = "rounded",
          focusable = true,
        })

        if not win or not vim.api.nvim_win_is_valid(win) then
          return
        end

        vim.api.nvim_set_current_win(win)

        vim.keymap.set("n", "q", "<cmd>close<cr>", {
          buffer = vim.api.nvim_win_get_buf(win),
          silent = true,
          desc = "Close hover",
        })

        vim.keymap.set("n", "<F1>", "<cmd>close<cr>", {
          buffer = vim.api.nvim_win_get_buf(win),
          silent = true,
          desc = "Close hover",
        })
      end)
    end, with_desc("Hover documentation"))

    map("n", "<leader>ld", function()
      focus_float(function()
        vim.diagnostic.open_float({
          border = "rounded",
          source = true,
          focusable = true,
        })
      end)
    end, with_desc("Line diagnostics"))

    map("n", "[d", function()
      vim.diagnostic.jump({
        count = -1,
        float = false,
      })

      focus_float(function()
        vim.diagnostic.open_float({
          border = "rounded",
          source = true,
          focusable = true,
        })
      end)
    end, with_desc("Previous diagnostic"))

    map("n", "]d", function()
      vim.diagnostic.jump({
        count = 1,
        float = false,
      })

      focus_float(function()
        vim.diagnostic.open_float({
          border = "rounded",
          source = true,
          focusable = true,
        })
      end)
    end, with_desc("Next diagnostic"))

    map("n", "<F2>", function()
      local params = vim.lsp.util.make_position_params(0, "utf-8")

      vim.lsp.buf_request(0, "textDocument/definition", params, function(_, result)
        if result and not vim.tbl_isempty(result) then
          vim.lsp.buf.definition()
        else
          vim.lsp.buf.declaration()
        end
      end)
    end, with_desc("Goto definition/declaration"))

    -- clangd-only extension; harmlessly warns when no pair exists.
    map("n", "<F4>", function()
      local params = { uri = vim.uri_from_bufnr(0) }

      ---@diagnostic disable-next-line: param-type-mismatch
      vim.lsp.buf_request(0, "textDocument/switchSourceHeader", params, function(err, result)
        if err then
          vim.notify("clangd switchSourceHeader failed: " .. err.message, vim.log.levels.ERROR)
          return
        end

        if not result then
          vim.notify("No corresponding source/header found", vim.log.levels.WARN)
          return
        end

        vim.cmd.edit(vim.uri_to_fname(result))
      end)
    end, with_desc("Switch source/header"))
  end,
})
