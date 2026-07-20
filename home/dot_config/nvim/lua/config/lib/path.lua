local M = {}

local function strip_trailing_separator(value)
  if value == "/" or value:match("^%a:[/\\]$") then
    return value
  end

  return value:gsub("[/\\]+$", "")
end

local function relative_from(value, root)
  if not value or not root then
    return nil
  end

  if value == root then
    return ""
  end

  local root_has_separator = root:match("[/\\]$") ~= nil

  for _, separator in ipairs({ "/", "\\" }) do
    local prefix = root_has_separator and root or (root .. separator)

    if vim.startswith(value, prefix) then
      return value:sub(#prefix + 1)
    end
  end

  return nil
end

function M.absolute(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end

  local absolute = vim.fn.fnamemodify(value, ":p")
  return strip_trailing_separator(vim.fs.normalize(absolute))
end

function M.real(value)
  local absolute = M.absolute(value)

  if not absolute then
    return nil
  end

  return strip_trailing_separator(vim.uv.fs_realpath(absolute) or absolute)
end

function M.is_absolute(value)
  if type(value) ~= "string" or value == "" then
    return false
  end

  if value:sub(1, 1) == "/" then
    return true
  end

  if value:match("^%a:[/\\]") then
    return true
  end

  return value:match("^[/\\][/\\]") ~= nil
end

function M.is_within(value, root)
  local relative = relative_from(M.absolute(value), M.absolute(root))

  if relative ~= nil then
    return true
  end

  return relative_from(M.real(value), M.real(root)) ~= nil
end

function M.relative(value, root)
  local relative = relative_from(M.absolute(value), M.absolute(root))

  if relative ~= nil then
    return relative
  end

  return relative_from(M.real(value), M.real(root))
end

return M
