-- Formatting order: external formatter by filetype, then attached LSP formatter.
-- Format-on-save is controlled by .nvim/project.json.

local M = {}

local function buffer_dir(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)

  if filename == "" then
    return nil
  end

  return vim.fs.dirname(filename)
end

local shell_formatter = {
  cmd = "shfmt",
  args = function(bufnr)
    return {
      "--filename",
      vim.api.nvim_buf_get_name(bufnr),
      "-",
    }
  end,
}

local xml_formatter = {
  cmd = "xmllint",
  args = function()
    return {
      "--format",
      "-",
    }
  end,
}

local external_formatters = {
  lua = {
    cmd = "stylua",
    args = function(bufnr)
      return {
        "--stdin-filepath",
        vim.api.nvim_buf_get_name(bufnr),
        "-",
      }
    end,
  },
  yaml = {
    cmd = "yamlfmt",
    cwd = buffer_dir,
    args = function()
      return {
        "-",
      }
    end,
  },

  toml = {
    cmd = "taplo",
    cwd = buffer_dir,
    args = function()
      return {
        "fmt",
        "-",
      }
    end,
  },

  sh = shell_formatter,
  zsh = shell_formatter,

  json = {
    cmd = "jq",
    args = function(bufnr)
      local ok, project_settings = pcall(require, "config.project_settings")

      local expandtab = vim.bo[bufnr].expandtab
      local tabstop = vim.bo[bufnr].tabstop

      if ok then
        expandtab = project_settings.get_option(bufnr, "expandtab", expandtab)
        tabstop = project_settings.get_option(bufnr, "tabstop", tabstop)
      end

      if expandtab == false then
        return { "--tab", "." }
      end

      return {
        "--indent",
        tostring(math.max(1, tabstop)),
        ".",
      }
    end,
  },

  markdown = {
    cmd = "mdformat",
    cwd = buffer_dir,
    args = function()
      return {
        "-",
      }
    end,
  },

  xml = xml_formatter,
  xslt = xml_formatter,
}

local function formatter_cwd(formatter, bufnr)
  if type(formatter.cwd) == "function" then
    return formatter.cwd(bufnr)
  end

  return formatter.cwd
end

local function is_real_file_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if vim.bo[bufnr].buftype ~= "" then
    return false
  end

  if vim.bo[bufnr].readonly or not vim.bo[bufnr].modifiable then
    return false
  end

  return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function format_enabled(bufnr)
  local ok, project_settings = pcall(require, "config.project_settings")
  if not ok then
    return false
  end

  return project_settings.format_on_save(bufnr)
end

local function has_lsp_formatter(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })

  for _, client in ipairs(clients) do
    if client:supports_method("textDocument/formatting", bufnr) then
      return true
    end
  end

  return false
end

local function buffer_text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local function replace_buffer_text(bufnr, text)
  text = text:gsub("\n$", "")
  local lines = vim.split(text, "\n", { plain = true })

  local current_buf = vim.api.nvim_get_current_buf()
  local view = current_buf == bufnr and vim.fn.winsaveview() or nil

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  if view then
    vim.fn.winrestview(view)
  end
end

local function formatter_args(formatter, bufnr)
  local args = formatter.args or {}

  if type(args) == "function" then
    args = args(bufnr)
  end

  if type(args) ~= "table" then
    return {}
  end

  return args
end

local function formatter_command(formatter, bufnr)
  local command = { formatter.cmd }

  for _, arg in ipairs(formatter_args(formatter, bufnr)) do
    table.insert(command, arg)
  end

  return command
end

local function format_with_external(bufnr, formatter, notify_missing)
  if vim.fn.executable(formatter.cmd) ~= 1 then
    if notify_missing then
      vim.notify("Formatter not found: " .. formatter.cmd, vim.log.levels.WARN)
    end
    return false
  end

  local result = vim
    .system(formatter_command(formatter, bufnr), {
      cwd = formatter_cwd(formatter, bufnr),
      stdin = buffer_text(bufnr),
      text = true,
    })
    :wait()

  if result.code ~= 0 then
    vim.notify("Formatter failed: " .. formatter.cmd .. "\n" .. vim.trim(result.stderr or ""), vim.log.levels.WARN)
    return false
  end

  replace_buffer_text(bufnr, result.stdout or "")

  -- External formatters update the buffer directly; refresh timestamp state afterwards.
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("checktime")
  end)

  return true
end

local function format_with_lsp(bufnr, notify_missing)
  if not has_lsp_formatter(bufnr) then
    if notify_missing then
      vim.notify("No formatter attached", vim.log.levels.WARN)
    end
    return false
  end

  vim.lsp.buf.format({
    bufnr = bufnr,
    timeout_ms = 2000,
  })

  return true
end

local function format_buffer(bufnr, notify_missing)
  local formatter = external_formatters[vim.bo[bufnr].filetype]

  if formatter then
    return format_with_external(bufnr, formatter, notify_missing)
  end

  return format_with_lsp(bufnr, notify_missing)
end

function M.format(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if is_real_file_buffer(bufnr) then
    format_buffer(bufnr, true)
  end
end

function M.format_on_save(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if is_real_file_buffer(bufnr) and format_enabled(bufnr) then
    format_buffer(bufnr, false)
  end
end

vim.api.nvim_create_autocmd("BufWritePre", {
  callback = function(event)
    M.format_on_save(event.buf)
  end,
})

return M
