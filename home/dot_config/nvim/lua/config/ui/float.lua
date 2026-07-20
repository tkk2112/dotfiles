local M = {}

function M.close(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  vim.api.nvim_win_close(winid, true)
  return true
end

function M.close_all()
  local closed = false

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(winid)

    if config.relative ~= "" then
      closed = M.close(winid) or closed
    end
  end

  return closed
end

function M.map_close(bufnr, winid, keys, description)
  for _, key in ipairs(keys or { "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      M.close(winid)
    end, {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = description or "Close floating window",
    })
  end
end

function M.open_centered(lines, options)
  options = options or {}

  if type(lines) ~= "table" or vim.tbl_isempty(lines) then
    return nil, nil
  end

  local ui = vim.api.nvim_list_uis()[1]

  if not ui then
    return nil, nil
  end

  local available_height = math.max(1, ui.height - vim.o.cmdheight - 2)

  local maximum_width = math.max(20, math.floor(ui.width * (options.width_ratio or 0.9)))

  local maximum_height = math.max(4, math.floor(available_height * (options.height_ratio or 0.85)))

  local content_width = 1

  for _, line in ipairs(lines) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
  end

  local width = math.min(math.max(options.min_width or 20, content_width), maximum_width)

  local height = math.min(math.max(options.min_height or 1, #lines), maximum_height)

  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = options.filetype or "text"
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].swapfile = false

  local winid = vim.api.nvim_open_win(bufnr, options.focus ~= false, {
    relative = "editor",
    row = math.max(0, math.floor((available_height - height) / 2)),
    col = math.max(0, math.floor((ui.width - width) / 2)),
    width = width,
    height = height,
    border = options.border or "rounded",
    style = "minimal",
    title = options.title and (" " .. options.title .. " ") or nil,
    title_pos = options.title and "center" or nil,
    zindex = options.zindex or 60,
  })

  vim.wo[winid].conceallevel = 0
  vim.wo[winid].linebreak = options.wrap == true
  vim.wo[winid].wrap = options.wrap == true

  M.map_close(bufnr, winid, options.close_keys or { "q", "<Esc>" }, options.close_description)

  return bufnr, winid
end

return M
