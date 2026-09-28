local completion = require("config.llm.completion")

describe("local llm completion", function()
  local original_system

  local function setup(opts)
    opts = opts or {}

    completion.setup({
      service = opts.service or "inline",
      endpoint = opts.endpoint or "http://127.0.0.1:18080",
      autostart = opts.autostart ~= false,
    })
  end

  before_each(function()
    original_system = vim.system
  end)

  after_each(function()
    completion.stop()

    vim.system = original_system

    pcall(vim.api.nvim_del_augroup_by_name, "LlmLocalCompletion")
  end)

  it("becomes available after a successful health check", function()
    local callback
    local command

    vim.system = function(argv, _, cb)
      command = vim.deepcopy(argv)
      callback = cb

      return {
        wait = function()
          return {
            code = 0,
          }
        end,
      }
    end

    setup()

    assert.is_false(completion.available())

    assert.are.same({
      "curl",
      "--silent",
      "--show-error",
      "--fail",
      "--connect-timeout",
      "0.2",
      "--max-time",
      "0.5",
      "http://127.0.0.1:18080/health",
    }, command)

    callback({
      code = 0,
      stdout = '{"status":"ok"}',
      stderr = "",
    })

    assert.is_true(completion.available())
  end)

  it("leaves autostart services alone when unavailable", function()
    local commands = {}
    local callback

    vim.system = function(argv, _, cb)
      table.insert(commands, vim.deepcopy(argv))
      callback = cb

      return {
        wait = function()
          return {
            code = 0,
          }
        end,
      }
    end

    setup({
      autostart = true,
    })

    callback({
      code = 7,
      stdout = "",
      stderr = "connection refused",
    })

    assert.is_false(completion.available())

    assert.are.equal(1, #commands)
    assert.are.equal("curl", commands[1][1])
  end)

  it("acquires and releases a manual completion service", function()
    local commands = {}
    local callbacks = {}

    vim.system = function(argv, _, callback)
      table.insert(commands, vim.deepcopy(argv))

      if callback then
        table.insert(callbacks, callback)
      end

      return {
        wait = function()
          return {
            code = 0,
            stdout = "",
            stderr = "",
          }
        end,
      }
    end

    setup({
      autostart = false,
    })

    -- Manual services remain dormant when Neovim starts.
    assert.are.equal(0, #commands)

    completion.available()

    assert.are.equal("curl", commands[1][1])

    callbacks[1]({
      code = 7,
      stdout = "",
      stderr = "connection refused",
    })

    assert.are.same({
      "dotfiles-llm",
      "acquire",
      "inline",
      tostring(vim.fn.getpid()),
    }, commands[2])

    callbacks[2]({
      code = 0,
      stdout = "",
      stderr = "",
    })

    completion.stop()

    assert.are.same({
      "dotfiles-llm",
      "release",
      "inline",
      tostring(vim.fn.getpid()),
    }, commands[3])
  end)
end)
