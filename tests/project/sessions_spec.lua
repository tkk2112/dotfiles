local sessions = require("config.project_sessions")

describe("project sessions", function()
  it("does not reset the workspace when the target root is missing", function()
    local tmp = vim.fn.tempname()
    local missing = vim.fs.joinpath(tmp, "removed-worktree")
    local bufnr = vim.api.nvim_create_buf(true, false)
    local tabs = #vim.api.nvim_list_tabpages()
    local cwd = vim.uv.cwd()

    vim.fn.mkdir(tmp, "p")
    vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(tmp, "keep.txt"))

    local notify = vim.notify
    vim.notify = function() end

    local ok, result = pcall(sessions.switch, missing)

    vim.notify = notify

    assert.is_true(ok, result)
    assert.is_nil(result)
    assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    assert.are.equal(tabs, #vim.api.nvim_list_tabpages())
    assert.are.equal(cwd, vim.uv.cwd())

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmp, "rf")
  end)
end)
