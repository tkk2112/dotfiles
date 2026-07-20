local M = {}

local function encoded_lines(value)
  local ok_encode, encoded = pcall(vim.json.encode, value)

  if not ok_encode then
    return nil, tostring(encoded)
  end

  if vim.fn.executable("jq") == 1 then
    local result = vim
      .system({
        "jq",
        "--indent",
        "2",
        ".",
      }, {
        stdin = encoded,
        text = true,
      })
      :wait()

    if result.code == 0 then
      return vim.split(result.stdout or "", "\n", {
        plain = true,
        trimempty = true,
      })
    end
  end

  return { encoded }
end

function M.read(path)
  if type(path) ~= "string" or path == "" then
    return nil, "JSON path must be a non-empty string"
  end

  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local ok_read, lines = pcall(vim.fn.readfile, path)

  if not ok_read then
    return nil, tostring(lines)
  end

  local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))

  if not ok_decode then
    return nil, tostring(decoded)
  end

  return decoded
end

function M.write(path, value, options)
  options = options or {}

  if type(path) ~= "string" or path == "" then
    return nil, "JSON path must be a non-empty string"
  end

  if options.mkdir then
    local parent = vim.fs.dirname(path)

    if parent then
      local ok_mkdir, mkdir_error = pcall(vim.fn.mkdir, parent, "p")

      if not ok_mkdir or vim.fn.isdirectory(parent) == 0 then
        return nil, ok_mkdir and ("Could not create directory: " .. parent) or tostring(mkdir_error)
      end
    end
  end

  local lines, encode_error = encoded_lines(value)

  if not lines then
    return nil, encode_error
  end

  local temporary_path = path .. ".tmp"
  local ok_write, write_result = pcall(vim.fn.writefile, lines, temporary_path)

  if not ok_write or write_result ~= 0 then
    vim.fn.delete(temporary_path)
    return nil, ok_write and "writefile returned " .. write_result or tostring(write_result)
  end

  local ok_rename, rename_error = os.rename(temporary_path, path)

  if not ok_rename then
    vim.fn.delete(temporary_path)
    return nil, tostring(rename_error)
  end

  return true
end

return M
