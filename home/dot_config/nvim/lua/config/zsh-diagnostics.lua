local M = {}

local uv = vim.uv or vim.loop
local namespace = vim.api.nvim_create_namespace("zsh-syntax")
local runs = {}

local function parse_errors(stderr, line_count)
  local diagnostics = {}

  for raw_line in (stderr or ""):gmatch("[^\r\n]+") do
    -- Typical output:
    -- /tmp/nvim...zsh:42: parse error near `}'
    local line_number, message = raw_line:match("^.-:(%d+):%s*(.+)$")

    local lnum

    if line_number then
      -- Zsh reports one-based lines; Neovim uses zero-based lines.
      lnum = tonumber(line_number) - 1
    else
      -- A filename-based check should normally have a line number.
      -- Fall back to the final buffer line for unusual errors.
      lnum = math.max(line_count - 1, 0)
      message = raw_line:gsub("^zsh:%s*", "")
    end

    if line_count > 0 then
      lnum = math.min(math.max(lnum, 0), line_count - 1)
    else
      lnum = 0
    end

    diagnostics[#diagnostics + 1] = {
      lnum = lnum,
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      source = "zsh -n",
      message = message,
    }
  end

  return diagnostics
end

function M.check(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.bo[bufnr].filetype ~= "zsh" then
    return
  end

  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  runs[bufnr] = (runs[bufnr] or 0) + 1
  local run = runs[bufnr]

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local tmpfile = vim.fn.tempname() .. ".zsh"

  local write_ok, write_result = pcall(vim.fn.writefile, lines, tmpfile)

  if not write_ok or write_result ~= 0 then
    vim.notify("Could not create temporary file for zsh diagnostics", vim.log.levels.ERROR)
    return
  end

  vim.system({
    "zsh",
    "-f",
    "-n",
    "--",
    tmpfile,
  }, {
    text = true,
  }, function(result)
    uv.fs_unlink(tmpfile)

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      -- Ignore stale results from an earlier invocation.
      if runs[bufnr] ~= run then
        return
      end

      local stderr = vim.trim(result.stderr or "")

      -- Zsh may report a parse error on stderr while returning zero.
      if result.code == 0 and stderr == "" then
        vim.diagnostic.reset(namespace, bufnr)
        return
      end

      local diagnostics = parse_errors(stderr, #lines)

      if #diagnostics == 0 then
        diagnostics[1] = {
          lnum = math.max(#lines - 1, 0),
          col = 0,
          severity = vim.diagnostic.severity.ERROR,
          source = "zsh -n",
          message = ("syntax check failed with exit code %d"):format(result.code),
        }
      end

      vim.diagnostic.set(namespace, bufnr, diagnostics)
    end)
  end)
end

function M.setup()
  if vim.fn.executable("zsh") ~= 1 then
    vim.notify("Zsh diagnostics disabled: zsh was not found", vim.log.levels.WARN)
    return
  end

  local group = vim.api.nvim_create_augroup("zsh_syntax_diagnostics", { clear = true })

  vim.api.nvim_create_autocmd({
    "BufEnter",
    "BufWritePost",
    "InsertLeave",
    "TextChanged",
  }, {
    group = group,
    callback = function(event)
      M.check(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      -- Invalidates any asynchronous check still running.
      runs[event.buf] = (runs[event.buf] or 0) + 1
      vim.diagnostic.reset(namespace, event.buf)
    end,
  })

  vim.api.nvim_create_user_command("ZshCheck", function()
    M.check(0)
  end, {
    desc = "Check current Zsh buffer syntax",
    force = true,
  })
end

return M
