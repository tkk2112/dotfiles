local paths = require("config.lib.path")
local quickfix_watch = require("config.quickfix_watch")

local function real(path)
  return assert(paths.real(path))
end

local function with_tmpdir(callback)
  local root = vim.fn.tempname()

  vim.fn.mkdir(root, "p")
  root = real(root)

  local ok, err = xpcall(function()
    callback(root)
  end, debug.traceback)

  vim.fn.delete(root, "rf")

  if not ok then
    error(err)
  end
end

local function with_errorformat(errorformat, callback)
  local previous = vim.bo.errorformat

  vim.bo.errorformat = errorformat

  local ok, err = xpcall(callback, debug.traceback)

  vim.bo.errorformat = previous

  if not ok then
    error(err)
  end
end

local function wait_until(predicate)
  assert.is_true(vim.wait(5000, predicate, 10))
end

local function write_file(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "test" }, path)

  return real(path)
end

local function qflist()
  return vim.fn.getqflist({
    title = 1,
    context = 1,
    idx = 0,
    items = 1,
  })
end

local function diagnostics_for_watch(bufnr, id)
  local diagnostics = {}

  for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
    if diagnostic.user_data and diagnostic.user_data.quickfix_watch == id then
      table.insert(diagnostics, diagnostic)
    end
  end

  return diagnostics
end

describe("quickfix watch", function()
  before_each(function()
    quickfix_watch.stop_all(false, "sigkill")
    vim.fn.setqflist({}, "r")
    pcall(vim.cmd, "silent cclose")
  end)

  after_each(function()
    quickfix_watch.stop_all(false, "sigkill")
    vim.fn.setqflist({}, "r")
    pcall(vim.cmd, "silent cclose")
  end)

  it("validates watcher-specific options", function()
    with_tmpdir(function(tmp)
      with_errorformat("%m", function()
        local result, err = quickfix_watch.watch({
          argv = { "true" },
          cwd = tmp,
          open = "never",
        })

        assert.is_nil(result)
        assert.are.equal("Quickfix watch id must be a non-empty string", err)

        result, err = quickfix_watch.watch({
          id = "test",
          argv = { "true" },
          cwd = tmp,
          root = "",
          open = "never",
        })

        assert.is_nil(result)
        assert.are.equal("Quickfix watch root must be a non-empty string", err)

        result, err = quickfix_watch.watch({
          id = "test",
          argv = { "true" },
          cwd = tmp,
          debounce_ms = 25,
          open = "never",
        })

        assert.is_nil(result)
        assert.are.equal("Quickfix watch debounce_ms must be at least 50", err)

        result, err = quickfix_watch.watch({
          id = "test",
          argv = { "true" },
          cwd = tmp,
          diagnostics = "sometimes",
          open = "never",
        })

        assert.is_nil(result)
        assert.is_truthy(err:find("Invalid quickfix watch diagnostics mode", 1, true))
      end)
    end)
  end)

  it("runs a build and reports successful watcher state", function()
    with_tmpdir(function(tmp)
      with_errorformat("%m", function()
        local result = assert(quickfix_watch.watch({
          id = "success",
          title = "successful build",
          argv = {
            "sh",
            "-c",
            "exit 0",
          },
          cwd = tmp,
          open = "never",
        }))

        assert.are.equal("started", result.status)
        assert.is_true(quickfix_watch.is_watching("success"))

        local building = assert(quickfix_watch.watch_status())

        assert.are.equal("success", building.id)
        assert.are.equal("building", building.state)
        assert.are.equal("WATCH …", quickfix_watch.statusline())
        assert.are.equal("DiagnosticWarn", quickfix_watch.statusline_color())

        wait_until(function()
          local status = quickfix_watch.watch_status()

          return status and status.state == "success"
        end)

        local status = assert(quickfix_watch.watch_status())

        assert.are.equal("success", status.id)
        assert.are.equal("successful build", status.title)
        assert.are.equal("success", status.state)
        assert.are.equal(0, status.items)
        assert.are.equal(0, status.exit_code)
        assert.are.equal(tmp, status.cwd)

        assert.are.equal("WATCH ✓", quickfix_watch.statusline())
        assert.are.equal("DiagnosticOk", quickfix_watch.statusline_color())

        local info = qflist()

        assert.are.equal("successful build [watch]", info.title)

        assert.are.same({
          cwd = tmp,
          watch = true,
          watch_id = "success",
        }, info.context)
      end)
    end)
  end)

  it("reports failed builds and publishes diagnostics", function()
    with_tmpdir(function(tmp)
      local source = write_file(vim.fs.joinpath(tmp, "source.c"))

      with_errorformat("%f:%l:%c:%t:%m", function()
        local result = assert(quickfix_watch.watch({
          id = "failure",
          title = "failing build",
          argv = {
            "sh",
            "-c",
            table.concat({
              [[printf '%s\n' 'source.c:6:4:E:broken']],
              [[exit 2]],
            }, "; "),
          },
          cwd = tmp,
          open = "never",
          diagnostics = "always",
        }))

        assert.are.equal("started", result.status)

        wait_until(function()
          local status = quickfix_watch.watch_status()

          return status and status.state == "error"
        end)

        local status = assert(quickfix_watch.watch_status())

        assert.are.equal("error", status.state)
        assert.are.equal(2, status.exit_code)
        assert.are.equal(1, status.items)

        assert.are.equal("WATCH ✗1", quickfix_watch.statusline())

        assert.are.equal("DiagnosticError", quickfix_watch.statusline_color())

        local info = qflist()

        assert.are.equal("failing build [watch]", info.title)
        assert.are.equal(1, #info.items)

        local item = info.items[1]

        assert.are.equal(1, item.valid)
        assert.are.equal(6, item.lnum)
        assert.are.equal(4, item.col)
        assert.are.equal("E", item.type)
        assert.are.equal("broken", item.text)

        assert.are.equal(source, real(vim.api.nvim_buf_get_name(item.bufnr)))

        local diagnostics = diagnostics_for_watch(item.bufnr, "failure")

        assert.are.equal(1, #diagnostics)

        local diagnostic = diagnostics[1]

        assert.are.equal(5, diagnostic.lnum)
        assert.are.equal(3, diagnostic.col)
        assert.are.equal(vim.diagnostic.severity.ERROR, diagnostic.severity)
        assert.are.equal("broken", diagnostic.message)
        assert.are.equal("failing build", diagnostic.source)
      end)
    end)
  end)

  it("does not publish diagnostics when disabled", function()
    with_tmpdir(function(tmp)
      write_file(vim.fs.joinpath(tmp, "source.c"))

      with_errorformat("%f:%l:%c:%t:%m", function()
        assert(quickfix_watch.watch({
          id = "no-diagnostics",
          title = "quiet build",
          argv = {
            "sh",
            "-c",
            table.concat({
              [[printf '%s\n' 'source.c:3:2:E:broken']],
              [[exit 1]],
            }, "; "),
          },
          cwd = tmp,
          open = "never",
          diagnostics = "never",
        }))

        wait_until(function()
          local status = quickfix_watch.watch_status()

          return status and status.state == "error"
        end)

        local info = qflist()

        assert.are.equal(1, #info.items)

        local diagnostics = diagnostics_for_watch(info.items[1].bufnr, "no-diagnostics")

        assert.are.equal(0, #diagnostics)
      end)
    end)
  end)

  it("toggles an existing watcher off", function()
    with_tmpdir(function(tmp)
      with_errorformat("%m", function()
        local started = assert(quickfix_watch.watch({
          id = "toggle",
          argv = {
            "sh",
            "-c",
            "sleep 5",
          },
          cwd = tmp,
          open = "never",
        }))

        assert.are.equal("started", started.status)
        assert.is_true(quickfix_watch.is_watching("toggle"))

        local stopped = assert(quickfix_watch.watch({
          id = "toggle",
          argv = {
            "sh",
            "-c",
            "sleep 5",
          },
          cwd = tmp,
          open = "never",
        }))

        assert.are.equal("stopped", stopped.status)
        assert.is_false(quickfix_watch.is_watching("toggle"))
        assert.is_nil(quickfix_watch.watch_status())

        assert.are.equal("", quickfix_watch.statusline())
        assert.are.equal("Normal", quickfix_watch.statusline_color())
      end)
    end)
  end)

  it("allows only one watcher to own the quickfix list", function()
    with_tmpdir(function(tmp)
      with_errorformat("%m", function()
        assert(quickfix_watch.watch({
          id = "first",
          argv = {
            "sh",
            "-c",
            "sleep 5",
          },
          cwd = tmp,
          open = "never",
        }))

        assert.is_true(quickfix_watch.is_watching("first"))

        assert(quickfix_watch.watch({
          id = "second",
          title = "second build",
          argv = {
            "sh",
            "-c",
            "exit 0",
          },
          cwd = tmp,
          open = "never",
        }))

        assert.is_false(quickfix_watch.is_watching("first"))

        assert.is_true(quickfix_watch.is_watching("second"))

        wait_until(function()
          local status = quickfix_watch.watch_status()

          return status and status.id == "second" and status.state == "success"
        end)

        local status = assert(quickfix_watch.watch_status())

        assert.are.equal("second", status.id)

        local info = qflist()

        assert.are.equal("second build [watch]", info.title)
        assert.are.equal("second", info.context.watch_id)
      end)
    end)
  end)

  it("queues one follow-up build while already running", function()
    with_tmpdir(function(tmp)
      local marker = vim.fs.joinpath(tmp, "runs.txt")

      local command = table.concat({
        "printf 'run\\n' >> " .. vim.fn.shellescape(marker),
        "sleep 0.2",
      }, "; ")

      with_errorformat("%m", function()
        assert(quickfix_watch.watch({
          id = "pending",
          title = "pending build",
          argv = {
            "sh",
            "-c",
            command,
          },
          cwd = tmp,
          open = "never",
        }))

        local status = assert(quickfix_watch.watch_status())
        assert.are.equal("building", status.state)

        -- Multiple requests while the current build is running collapse
        -- into one pending rebuild.
        assert.is_true(quickfix_watch.build("pending"))
        assert.is_true(quickfix_watch.build("pending"))

        wait_until(function()
          if vim.fn.filereadable(marker) == 0 then
            return false
          end

          local runs = vim.fn.readfile(marker)
          local current = quickfix_watch.watch_status()

          return #runs == 2 and current and current.state == "success"
        end)

        assert.are.equal(2, #vim.fn.readfile(marker))

        local status_after = assert(quickfix_watch.watch_status())

        assert.are.equal("success", status_after.state)
        assert.are.equal(0, status_after.exit_code)
      end)
    end)
  end)

  it("passes the configured cwd and environment to builds", function()
    with_tmpdir(function(tmp)
      local marker = vim.fs.joinpath(tmp, "environment.txt")

      local command = string.format([[printf '%%s|%%s\n' "$PWD" "$WATCH_TEST_VALUE" > %s]], vim.fn.shellescape(marker))

      with_errorformat("%m", function()
        assert(quickfix_watch.watch({
          id = "environment",
          argv = {
            "sh",
            "-c",
            command,
          },
          cwd = tmp,
          env = {
            WATCH_TEST_VALUE = "configured",
          },
          open = "never",
        }))

        wait_until(function()
          local status = quickfix_watch.watch_status()

          return status and status.state == "success" and vim.fn.filereadable(marker) == 1
        end)

        assert.are.same({
          tmp .. "|configured",
        }, vim.fn.readfile(marker))
      end)
    end)
  end)
end)
