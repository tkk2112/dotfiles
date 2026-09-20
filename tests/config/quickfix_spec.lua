local paths = require("config.lib.path")
local quickfix = require("config.quickfix")

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

local function with_cwd(path, callback)
  local previous = vim.fn.getcwd()

  vim.api.nvim_set_current_dir(path)

  local ok, err = xpcall(callback, debug.traceback)

  vim.api.nvim_set_current_dir(previous)

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

local function wait_for(callback)
  local done = false
  local result
  local err

  callback(function(value, callback_err)
    result = value
    err = callback_err
    done = true
  end)

  assert.is_true(vim.wait(5000, function()
    return done
  end, 10))

  return result, err
end

local function write_file(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "test" }, path)

  return real(path)
end

local function quickfix_window()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local info = vim.fn.getwininfo(winid)[1]

    if info and info.quickfix == 1 and info.loclist == 0 then
      return winid
    end
  end

  return nil
end

describe("quickfix", function()
  before_each(function()
    vim.fn.setqflist({}, "r")
    pcall(vim.cmd, "silent cclose")
  end)

  after_each(function()
    vim.fn.setqflist({}, "r")
    pcall(vim.cmd, "silent cclose")
  end)

  it("validates common options", function()
    local _, err = quickfix.prepare(nil)
    assert.are.equal("Quickfix options must be a table", err)

    _, err = quickfix.prepare({})
    assert.are.equal("Quickfix argv must be a non-empty list", err)

    _, err = quickfix.prepare({
      argv = { "true" },
    })
    assert.are.equal("Quickfix cwd must be a non-empty string", err)

    _, err = quickfix.prepare({
      argv = { "true" },
      cwd = "/tmp",
      env = "wrong",
    })
    assert.are.equal("Quickfix env must be a table", err)

    _, err = quickfix.prepare({
      argv = { "true" },
      cwd = "/tmp",
      open = "sometimes",
    })

    assert.is_truthy(err:find("Invalid quickfix open mode", 1, true))
  end)

  it("rejects unsafe compiler names", function()
    with_tmpdir(function(tmp)
      local prepared, err = quickfix.prepare({
        argv = { "true" },
        cwd = tmp,
        compiler = "gcc | quit",
      })

      assert.is_nil(prepared)
      assert.is_truthy(err:find("Invalid compiler name", 1, true))
    end)
  end)

  it("uses the current errorformat by default", function()
    with_tmpdir(function(tmp)
      with_errorformat("%f:%l:%c:%t:%m", function()
        local prepared = assert(quickfix.prepare({
          argv = { "true" },
          cwd = tmp,
          open = "never",
        }))

        assert.are.equal("never", prepared.open)
        assert.are.equal("%f:%l:%c:%t:%m", prepared.errorformat)
      end)
    end)
  end)

  it("loads compiler errorformat without changing compiler state", function()
    with_tmpdir(function(tmp)
      local runtime = vim.fs.joinpath(tmp, "runtime")
      local compiler_dir = vim.fs.joinpath(runtime, "compiler")

      vim.fn.mkdir(compiler_dir, "p")

      vim.fn.writefile({
        [[if exists("current_compiler")]],
        [[  finish]],
        [[endif]],
        [[let current_compiler = "quickfix-test"]],
        [[CompilerSet makeprg=quickfix-test]],
        [[CompilerSet errorformat=%f:%l:%c:%t:%m]],
        [[CompilerSet makeencoding=latin1]],
      }, vim.fs.joinpath(compiler_dir, "quickfix-test.vim"))

      local previous_rtp = vim.o.runtimepath
      local previous_makeprg = vim.bo.makeprg
      local previous_errorformat = vim.bo.errorformat
      local previous_makeencoding = vim.bo.makeencoding
      local previous_compiler = vim.b.current_compiler

      vim.opt.runtimepath:prepend(runtime)

      vim.bo.makeprg = "original-make"
      vim.bo.errorformat = "ORIGINAL"
      vim.bo.makeencoding = "utf-8"
      vim.b.current_compiler = "original"

      local ok, err = xpcall(function()
        local prepared = assert(quickfix.prepare({
          argv = { "true" },
          cwd = tmp,
          compiler = "quickfix-test",
        }))

        assert.are.equal("%f:%l:%c:%t:%m", prepared.errorformat)

        assert.are.equal("original-make", vim.bo.makeprg)
        assert.are.equal("ORIGINAL", vim.bo.errorformat)
        assert.are.equal("utf-8", vim.bo.makeencoding)
        assert.are.equal("original", vim.b.current_compiler)
      end, debug.traceback)

      vim.o.runtimepath = previous_rtp
      vim.bo.makeprg = previous_makeprg
      vim.bo.errorformat = previous_errorformat
      vim.bo.makeencoding = previous_makeencoding
      vim.b.current_compiler = previous_compiler

      if not ok then
        error(err)
      end
    end)
  end)

  it("parses relative diagnostics against the command cwd", function()
    with_tmpdir(function(tmp)
      local project = vim.fs.joinpath(tmp, "project")
      local source = write_file(vim.fs.joinpath(project, "src", "main.c"))

      local outside = vim.fs.joinpath(tmp, "outside")
      vim.fn.mkdir(outside, "p")
      outside = real(outside)

      with_cwd(outside, function()
        local parsed = assert(quickfix.parse_result(project, {
          code = 1,
          stdout = "src/main.c:12:3:E:broken\n",
          stderr = "",
        }, "%f:%l:%c:%t:%m"))

        assert.are.equal(outside, real(vim.fn.getcwd()))

        assert.are.equal(1, #parsed.parsed_items)

        local item = parsed.parsed_items[1]

        assert.are.equal(1, item.valid)
        assert.are.equal(12, item.lnum)
        assert.are.equal(3, item.col)
        assert.are.equal("E", item.type)
        assert.are.equal("broken", item.text)

        assert.are.equal(source, real(vim.api.nvim_buf_get_name(item.bufnr)))
      end)
    end)
  end)

  it("strips ANSI sequences and normalizes carriage returns", function()
    with_tmpdir(function(tmp)
      local parsed = assert(quickfix.parse_result(tmp, {
        code = 0,
        stdout = "\27[31mfirst\27[0m\rsecond",
        stderr = "",
      }, "%m"))

      assert.are.same({
        "first",
        "second",
      }, parsed.lines)
    end)
  end)

  it("combines stdout before stderr", function()
    with_tmpdir(function(tmp)
      local parsed = assert(quickfix.parse_result(tmp, {
        code = 0,
        stdout = "stdout-one\nstdout-two\n",
        stderr = "stderr-one\n",
      }, "%m"))

      assert.are.same({
        "stdout-one",
        "stdout-two",
        "stderr-one",
      }, parsed.lines)
    end)
  end)

  it("falls back to raw output when a failed command has no parsed diagnostics", function()
    with_tmpdir(function(tmp)
      local parsed = assert(quickfix.parse_result(tmp, {
        code = 7,
        stdout = "the build exploded\n",
        stderr = "details here\n",
      }, "%-G%.%#"))

      assert.are.equal(0, #parsed.parsed_items)

      assert.are.same({
        {
          text = "the build exploded",
        },
        {
          text = "details here",
        },
      }, parsed.displayed_items)
    end)
  end)

  it("does not turn ignored output into errors after a successful command", function()
    with_tmpdir(function(tmp)
      local parsed = assert(quickfix.parse_result(tmp, {
        code = 0,
        stdout = "ordinary build chatter\n",
        stderr = "",
      }, "%-G%.%#"))

      assert.are.equal(0, #parsed.parsed_items)
      assert.are.equal(0, #parsed.displayed_items)
    end)
  end)

  it("finds the first jumpable quickfix item", function()
    assert.is_nil(quickfix.first_valid_index({}))

    assert.are.equal(
      3,
      quickfix.first_valid_index({
        {
          valid = 0,
          lnum = 0,
        },
        {
          valid = 1,
          lnum = 0,
        },
        {
          valid = 1,
          lnum = 12,
        },
        {
          valid = 1,
          lnum = 20,
        },
      })
    )
  end)

  it("replaces the quickfix list and selects its first valid item", function()
    with_tmpdir(function(tmp)
      local source = write_file(vim.fs.joinpath(tmp, "source.c"))

      local parsed = assert(quickfix.parse_result(tmp, {
        code = 1,
        stdout = table.concat({
          "build started",
          "source.c:7:2:E:broken",
          "",
        }, "\n"),
        stderr = "",
      }, "%f:%l:%c:%t:%m"))

      assert.are.equal(2, #parsed.displayed_items)
      assert.are.equal(0, parsed.displayed_items[1].valid)
      assert.are.equal(1, parsed.displayed_items[2].valid)

      quickfix.replace("test build", parsed.displayed_items, {
        cwd = tmp,
        compiler = "test",
        watch = false,
      })

      local info = vim.fn.getqflist({
        title = 1,
        context = 1,
        idx = 0,
        items = 1,
      })

      assert.are.equal("test build", info.title)
      assert.are.equal(2, info.idx)

      assert.are.same({
        cwd = tmp,
        compiler = "test",
        watch = false,
      }, info.context)

      assert.are.equal(2, #info.items)

      local item = info.items[2]

      assert.are.equal(1, item.valid)
      assert.are.equal(7, item.lnum)
      assert.are.equal(2, item.col)

      assert.are.equal(source, real(vim.api.nvim_buf_get_name(item.bufnr)))
    end)
  end)

  it("keeps quickfix closed in never mode", function()
    quickfix.replace("hidden build", {
      {
        text = "something",
      },
    }, {})

    quickfix.open("never", 1, false)

    assert.is_nil(quickfix_window())
  end)

  it("runs a command asynchronously and publishes parsed results", function()
    with_tmpdir(function(tmp)
      local source = write_file(vim.fs.joinpath(tmp, "source.c"))

      with_errorformat("%f:%l:%c:%t:%m", function()
        local result, err = wait_for(function(done)
          local process, start_err = quickfix.run({
            argv = {
              "sh",
              "-c",
              table.concat({
                [[printf '%s\n' 'source.c:4:2:E:compile failed']],
                [[printf '%s\n' 'extra stderr' >&2]],
                [[exit 3]],
              }, "; "),
            },
            cwd = tmp,
            open = "never",
            title = "test command",
          }, done)

          assert.is_not_nil(process)
          assert.is_nil(start_err)
        end)

        assert.is_nil(err)
        assert.is_not_nil(result)

        assert.are.equal(3, result.code)

        assert.is_truthy(result.stdout:find("source.c:4:2:E:compile failed", 1, true))

        assert.is_truthy(result.stderr:find("extra stderr", 1, true))

        assert.are.equal(2, #result.items)

        local valid_index = assert(quickfix.first_valid_index(result.items))

        assert.are.equal(1, valid_index)

        local item = result.items[valid_index]

        assert.are.equal(1, item.valid)
        assert.are.equal(4, item.lnum)
        assert.are.equal(2, item.col)
        assert.are.equal("E", item.type)
        assert.are.equal("compile failed", item.text)

        assert.are.equal(source, real(vim.api.nvim_buf_get_name(item.bufnr)))

        local stderr_item = result.items[2]

        assert.are.equal(0, stderr_item.valid)
        assert.are.equal("extra stderr", stderr_item.text)

        local info = vim.fn.getqflist({
          title = 1,
          context = 1,
        })

        assert.are.equal("test command", info.title)

        assert.are.same({
          cwd = tmp,
          watch = false,
        }, info.context)
      end)
    end)
  end)

  it("passes cwd and environment to the command", function()
    with_tmpdir(function(tmp)
      with_errorformat("%m", function()
        local result, err = wait_for(function(done)
          local process, start_err = quickfix.run({
            argv = {
              "sh",
              "-c",
              [[printf '%s|%s\n' "$PWD" "$QUICKFIX_TEST_VALUE"]],
            },
            cwd = tmp,
            env = {
              QUICKFIX_TEST_VALUE = "from-environment",
            },
            open = "never",
          }, done)

          assert.is_not_nil(process)
          assert.is_nil(start_err)
        end)

        assert.is_nil(err)

        assert.are.equal(tmp .. "|from-environment\n", result.stdout)
      end)
    end)
  end)
end)
