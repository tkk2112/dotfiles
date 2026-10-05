local lsp_ui = require("config.lsp_ui")

describe("LSP UI", function()
  local bufnr
  local original_document_highlight
  local original_clear_references

  before_each(function()
    bufnr = vim.api.nvim_create_buf(true, false)

    original_document_highlight = vim.lsp.buf.document_highlight
    original_clear_references = vim.lsp.buf.clear_references
  end)

  after_each(function()
    vim.lsp.buf.document_highlight = original_document_highlight
    vim.lsp.buf.clear_references = original_clear_references

    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("highlights references on CursorHold", function()
    local highlighted = false

    vim.lsp.buf.document_highlight = function()
      highlighted = true
    end

    lsp_ui.setup_document_highlight(bufnr, {
      supports_method = function(_, method)
        return method == "textDocument/documentHighlight"
      end,
    })

    vim.api.nvim_exec_autocmds("CursorHold", {
      buffer = bufnr,
    })

    assert.is_true(highlighted)
  end)

  it("clears references when the cursor moves", function()
    local cleared = false

    vim.lsp.buf.clear_references = function()
      cleared = true
    end

    lsp_ui.setup_document_highlight(bufnr, {
      supports_method = function(_, method)
        return method == "textDocument/documentHighlight"
      end,
    })

    vim.api.nvim_exec_autocmds("CursorMoved", {
      buffer = bufnr,
    })

    assert.is_true(cleared)
  end)

  it("does nothing when the server does not support document highlights", function()
    lsp_ui.setup_document_highlight(bufnr, {
      supports_method = function()
        return false
      end,
    })

    local autocmds = vim.api.nvim_get_autocmds({
      group = "dotfiles_lsp_document_highlight",
      buffer = bufnr,
    })

    assert.are.equal(0, #autocmds)
  end)
end)
