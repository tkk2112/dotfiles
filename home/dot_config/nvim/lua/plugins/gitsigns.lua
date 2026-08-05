local function notify_git_show(message)
  vim.schedule(function()
    vim.notify(message, vim.log.levels.WARN, {
      title = "Git show",
    })
  end)
end

local function parse_git_show_locations(lines)
  local locations = {}
  local path
  local new_line

  for index, line in ipairs(lines) do
    if line:match("^diff %-%-git ") then
      path = nil
      new_line = nil
    elseif line == "+++ /dev/null" then
      path = nil
      new_line = nil
    else
      local destination = line:match("^%+%+%+ b/(.*)$")

      if destination then
        path = destination
        new_line = nil
      else
        local hunk_start = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")

        if hunk_start then
          new_line = tonumber(hunk_start)
        elseif path and new_line then
          local prefix = line:sub(1, 1)

          if prefix == " " or prefix == "+" then
            locations[index] = {
              path = path,
              line = new_line,
              text = line:sub(2),
            }

            new_line = new_line + 1
          elseif prefix ~= "-" and prefix ~= "\\" then
            new_line = nil
          end
        end
      end
    end
  end

  return locations
end

local function find_matching_line(lines, expected_line, expected_text)
  if #lines == 0 then
    return nil
  end

  expected_line = math.max(1, math.min(expected_line, #lines))

  if lines[expected_line] == expected_text then
    return expected_line
  end

  local nearest_line
  local nearest_distance

  for line, text in ipairs(lines) do
    if text == expected_text then
      local distance = math.abs(line - expected_line)

      if not nearest_distance or distance < nearest_distance then
        nearest_line = line
        nearest_distance = distance
      end
    end
  end

  return nearest_line
end

local function current_file_lines(path)
  local bufnr = vim.fn.bufnr(path)

  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  local ok, lines = pcall(vim.fn.readfile, path)

  if not ok then
    return nil
  end

  return lines
end

local function open_git_show_window(root, sha, output)
  vim.schedule(function()
    local source_window = vim.api.nvim_get_current_win()
    local lines = vim.split(output, "\n", { plain = true })

    if lines[#lines] == "" then
      table.remove(lines)
    end

    local locations = parse_git_show_locations(lines)
    local buffer = vim.api.nvim_create_buf(false, true)

    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].filetype = "git"

    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false

    local width = math.max(1, math.min(math.floor(vim.o.columns * 0.85), vim.o.columns - 4))

    local height = math.max(1, math.min(math.floor(vim.o.lines * 0.80), vim.o.lines - 4))

    local window = vim.api.nvim_open_win(buffer, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      border = "rounded",
      style = "minimal",
      title = string.format(" git show %s  <Enter>: jump ", sha:sub(1, 7)),
      title_pos = "center",
    })

    vim.wo[window].wrap = false
    vim.wo[window].cursorline = true

    local function close()
      if vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
      end
    end

    local function jump_to_line()
      local popup_line = vim.api.nvim_win_get_cursor(window)[1]
      local location = locations[popup_line]

      if not location then
        notify_git_show("Place the cursor on an added or context line in the diff")
        return
      end

      local path = root .. "/" .. location.path

      if vim.fn.filereadable(path) ~= 1 then
        notify_git_show(string.format("File no longer exists: %s", location.path))
        return
      end

      local file_lines = current_file_lines(path)

      if not file_lines then
        notify_git_show(string.format("Could not read: %s", location.path))
        return
      end

      local target_line = find_matching_line(file_lines, location.line, location.text)

      if not target_line then
        notify_git_show(string.format("The selected line no longer exists in %s", location.path))
        return
      end

      close()

      if vim.api.nvim_win_is_valid(source_window) then
        vim.api.nvim_set_current_win(source_window)
      end

      local ok, error_message = pcall(vim.cmd.edit, vim.fn.fnameescape(path))

      if not ok then
        notify_git_show(tostring(error_message))
        return
      end

      local line_count = vim.api.nvim_buf_line_count(0)
      target_line = math.min(target_line, line_count)

      vim.api.nvim_win_set_cursor(0, { target_line, 0 })
      vim.cmd("normal! zz")
    end

    vim.keymap.set("n", "<CR>", jump_to_line, {
      buffer = buffer,
      silent = true,
      nowait = true,
      desc = "Jump to current file",
    })

    vim.keymap.set("n", "q", close, {
      buffer = buffer,
      silent = true,
      nowait = true,
    })

    vim.keymap.set("n", "<Esc>", close, {
      buffer = buffer,
      silent = true,
      nowait = true,
    })
  end)
end

local function show_line_commit()
  local file = vim.api.nvim_buf_get_name(0)

  if file == "" then
    notify_git_show("The current buffer is not a file")
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local directory = vim.fs.dirname(file)

  vim.system({
    "git",
    "-C",
    directory,
    "rev-parse",
    "--show-toplevel",
  }, {
    text = true,
  }, function(root_result)
    if root_result.code ~= 0 then
      notify_git_show("The current file is not inside a Git repository")
      return
    end

    local root = vim.fs.normalize(vim.trim(root_result.stdout or ""))
    local normalized_file = vim.fs.normalize(file)
    local prefix = root .. "/"

    if normalized_file:sub(1, #prefix) ~= prefix then
      notify_git_show("Could not resolve the file relative to the repository")
      return
    end

    local relative_file = normalized_file:sub(#prefix + 1)

    vim.system({
      "git",
      "-C",
      root,
      "blame",
      "--porcelain",
      "-L",
      string.format("%d,%d", line, line),
      "--",
      relative_file,
    }, {
      text = true,
    }, function(blame_result)
      if blame_result.code ~= 0 then
        notify_git_show(vim.trim(blame_result.stderr or "Git blame failed"))
        return
      end

      local sha = (blame_result.stdout or ""):match("^(%x+)")

      if not sha or sha:match("^0+$") then
        notify_git_show("The current line has not been committed")
        return
      end

      vim.system({
        "git",
        "-C",
        root,
        "-c",
        "core.quotePath=false",
        "show",
        "--no-color",
        "--no-ext-diff",
        "--decorate=short",
        "--diff-merges=first-parent",
        sha,
      }, {
        text = true,
      }, function(show_result)
        if show_result.code ~= 0 then
          notify_git_show(vim.trim(show_result.stderr or "Git show failed"))
          return
        end

        open_git_show_window(root, sha, show_result.stdout or "")
      end)
    end)
  end)
end

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

        map("n", "<leader>gs", show_line_commit, with_desc("Show line commit"))
      end,
    },
  },
}
