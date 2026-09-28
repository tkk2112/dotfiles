local context = require("config.project_context")
local index = require("config.project_index")
local llm = require("config.llm")
local paths = require("config.lib.path")
local scope = require("config.project_scope")

local function real(path)
  return assert(paths.real(path))
end

local function absolute(path)
  return assert(paths.absolute(path))
end

local function mkdir(path)
  vim.fn.mkdir(path, "p")
  return real(path)
end

local function write_json(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(value) }, path)
  return absolute(path)
end

local function write_file(path, contents)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ contents or "" }, path)
  return absolute(path)
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

local function reset_index()
  vim.fn.delete(index.path())
  vim.fn.delete(index.legacy_path())
end

describe("llm configuration", function()
  before_each(reset_index)
  after_each(reset_index)

  it("is disabled by default", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
      })

      with_cwd(root, function()
        local config = llm.config()

        assert.is_false(config.enabled)
        assert.are.equal("codex", config.backend)
        assert.are.same({}, config.instructions)
      end)
    end)
  end)

  it("loads project LLM settings", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local instructions = write_file(vim.fs.joinpath(root, "AGENTS.md"), "Project instructions")

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        llm = {
          enabled = true,
          backend = "claude",
          instructions = {
            "AGENTS.md",
          },
        },
      })

      with_cwd(root, function()
        local config = llm.config()

        assert.is_true(config.enabled)
        assert.are.equal("claude", config.backend)
        assert.are.same({ instructions }, config.instructions)
      end)
    end)
  end)

  it("inherits project settings and applies subproject overrides", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local subproject = mkdir(vim.fs.joinpath(root, "tools", "stardust"))

      local project_instructions = write_file(vim.fs.joinpath(root, "AGENTS.md"), "Project instructions")
      local scope_instructions = write_file(vim.fs.joinpath(subproject, "LLM.md"), "Stardust instructions")

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        llm = {
          enabled = true,
          backend = "codex",
          instructions = {
            "AGENTS.md",
          },
        },
        subprojects = {
          stardust = {
            root = "tools/stardust",
          },
        },
      })

      write_json(vim.fs.joinpath(root, ".nvim", "subprojects", "stardust.json"), {
        global = {},
        llm = {
          backend = "claude",
          instructions = {
            "LLM.md",
          },
        },
      })

      with_cwd(root, function()
        assert(context.resolve(root))
        assert(scope.select(root, "stardust"))

        local config = llm.config()

        assert.is_true(config.enabled)
        assert.are.equal("claude", config.backend)
        assert.are.equal(subproject, config.scope_root)
        assert.are.same({
          project_instructions,
          scope_instructions,
        }, config.instructions)
      end)
    end)
  end)

  it("does not allow instruction files to escape their project root", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))

      write_file(vim.fs.joinpath(tmp, "outside.md"), "Do not load me")

      write_json(vim.fs.joinpath(root, ".nvim", "project.json"), {
        root = "..",
        global = {},
        llm = {
          enabled = true,
          instructions = {
            "../outside.md",
          },
        },
      })

      with_cwd(root, function()
        local config = llm.config()

        assert.are.same({}, config.instructions)
        assert.are.same({ "../outside.md" }, config.invalid_instructions)
      end)
    end)
  end)
end)

describe("llm structured execution", function()
  local original_config
  local original_backend
  local original_system
  local original_path
  local original_codecompanion

  local function make_executable(path)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({
      "#!/bin/sh",
      "exit 0",
    }, path)
    vim.fn.setfperm(path, "rwxr-xr-x")

    return absolute(path)
  end

  local function stub_config(root, backend, instructions)
    llm.config = function()
      return {
        project_root = root,
        scope_root = root,
        enabled = true,
        backend = backend,
        instructions = instructions or {},
        missing_instructions = {},
        invalid_instructions = {},
      }
    end

    llm.backend = function(config)
      return config.backend
    end
  end

  local function run_and_wait(prompt)
    local done = false
    local result = {}

    local handle = llm.run_structured(prompt, function(output, err, backend)
      result.output = output
      result.err = err
      result.backend = backend
      done = true
    end)

    assert.is_true(vim.wait(1000, function()
      return done
    end, 10))

    return handle, result
  end

  before_each(function()
    original_config = llm.config
    original_backend = llm.backend
    original_system = vim.system
    original_path = vim.env.PATH
    original_codecompanion = package.loaded.codecompanion
  end)

  after_each(function()
    llm.config = original_config
    llm.backend = original_backend
    vim.system = original_system
    vim.env.PATH = original_path
    package.loaded.codecompanion = original_codecompanion
  end)

  it("does nothing when the selected backend is unavailable", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      stub_config(root, "codex")

      -- Deliberately exclude the real machine PATH. This test must behave
      -- identically whether Codex happens to be installed or not.
      vim.env.PATH = bin

      local system_called = false

      vim.system = function()
        system_called = true
        error("vim.system must not be called")
      end

      local handle, result = run_and_wait("test")

      assert.is_nil(handle)
      assert.is_false(system_called)
      assert.is_nil(result.output)
      assert.are.equal("codex", result.backend)
      assert.matches("not available in PATH: codex", result.err)
    end)
  end)

  it("runs Codex with repository tools disabled", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "codex"))

      stub_config(root, "codex")
      vim.env.PATH = bin

      local invocation

      vim.system = function(command, opts, callback)
        invocation = {
          command = vim.deepcopy(command),
          opts = vim.deepcopy(opts),
        }

        callback({
          code = 0,
          stdout = table.concat({
            vim.json.encode({
              type = "thread.started",
              thread_id = "test",
            }),
            vim.json.encode({
              type = "item.completed",
              item = {
                type = "agent_message",
                text = "LLM OK",
              },
            }),
          }, "\n"),
          stderr = "",
        })

        return {
          kill = function() end,
        }
      end

      local handle, result = run_and_wait("Respond exactly with: LLM OK")

      assert.is_not_nil(handle)

      assert.are.same({
        "codex",
        "--sandbox",
        "read-only",
        "--ask-for-approval",
        "never",

        "-c",
        "features.apps=false",
        "-c",
        "features.code_mode=false",
        "-c",
        "features.code_mode_only=false",
        "-c",
        "features.context_management=false",
        "-c",
        "features.current_time_reminder=false",
        "-c",
        "features.deferred_executor=false",
        "-c",
        "features.enable_fanout=false",
        "-c",
        "features.goals=false",
        "-c",
        "features.hooks=false",
        "-c",
        "features.image_generation=false",
        "-c",
        "features.memories=false",
        "-c",
        "features.multi_agent=false",
        "-c",
        "features.multi_agent_v2=false",
        "-c",
        "features.plugins=false",
        "-c",
        "features.request_permissions_tool=false",
        "-c",
        "features.shell_snapshot=false",
        "-c",
        "features.shell_tool=false",
        "-c",
        "features.standalone_web_search=false",
        "-c",
        "features.token_budget=false",
        "-c",
        "features.tool_suggest=false",
        "-c",
        "features.unified_exec=false",
        "-c",
        "features.view_image=false",
        "-c",
        "cloud.skills.enabled=false",
        "-c",
        "skills.include_instructions=false",
        "-c",
        "tools.experimental_request_user_input.enabled=false",
        "-c",
        "tools.update_plan.enabled=false",
        "-c",
        'web_search="disabled"',
        "-c",
        "mcp_servers={}",

        "exec",
        "--ephemeral",
        "--ignore-user-config",
        "--ignore-rules",
        "--skip-git-repo-check",
        "--json",
        "-",
      }, invocation.command)

      assert.are.equal(root, invocation.opts.cwd)
      assert.are.equal("Respond exactly with: LLM OK", invocation.opts.stdin)
      assert.is_true(invocation.opts.text)

      assert.are.equal("LLM OK", result.output)
      assert.is_nil(result.err)
      assert.are.equal("codex", result.backend)
    end)
  end)

  it("uses the final Codex agent message", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "codex"))

      stub_config(root, "codex")
      vim.env.PATH = bin

      vim.system = function(_, _, callback)
        callback({
          code = 0,
          stdout = table.concat({
            vim.json.encode({
              type = "item.completed",
              item = {
                type = "agent_message",
                text = "intermediate",
              },
            }),
            vim.json.encode({
              type = "item.completed",
              item = {
                type = "agent_message",
                text = "final response",
              },
            }),
          }, "\n"),
          stderr = "",
        })

        return {}
      end

      local _, result = run_and_wait("test")

      assert.are.equal("final response", result.output)
      assert.is_nil(result.err)
    end)
  end)

  it("runs Claude with tools disabled", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "claude"))

      stub_config(root, "claude")
      vim.env.PATH = bin

      local invocation

      vim.system = function(command, opts, callback)
        invocation = {
          command = vim.deepcopy(command),
          opts = vim.deepcopy(opts),
        }

        callback({
          code = 0,
          stdout = "LLM OK\n",
          stderr = "",
        })

        return {
          kill = function() end,
        }
      end

      local handle, result = run_and_wait("Respond exactly with: LLM OK")

      assert.is_not_nil(handle)

      assert.are.same({
        "claude",
        "-p",
        "--restricted",
        "--tools",
        "",
        "--disallowed-tools",
        "*",
        "--permission-mode",
        "dontAsk",
        "--no-session-persistence",
        "--output-format",
        "text",
        "Follow the request provided on stdin. Return only the requested result.",
      }, invocation.command)

      assert.are.equal(root, invocation.opts.cwd)
      assert.are.equal("Respond exactly with: LLM OK", invocation.opts.stdin)

      assert.are.equal("LLM OK", result.output)
      assert.is_nil(result.err)
      assert.are.equal("claude", result.backend)
    end)
  end)

  it("injects configured instructions into one-shot requests", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "codex"))

      local instructions = write_file(vim.fs.joinpath(root, "AGENTS.md"), "Always use modern C++.")

      stub_config(root, "codex", {
        instructions,
      })

      vim.env.PATH = bin

      local stdin

      vim.system = function(_, opts, callback)
        stdin = opts.stdin

        callback({
          code = 0,
          stdout = vim.json.encode({
            type = "item.completed",
            item = {
              type = "agent_message",
              text = "done",
            },
          }),
          stderr = "",
        })

        return {}
      end

      local _, result = run_and_wait("Review this code")

      assert.is_nil(result.err)

      assert.matches("Follow these project instructions before answering:", stdin, 1, true)

      assert.matches("Always use modern C++.", stdin, 1, true)

      assert.matches("Review this code", stdin, 1, true)
    end)
  end)

  it("reports provider failures without throwing", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "codex"))

      stub_config(root, "codex")
      vim.env.PATH = bin

      vim.system = function(_, _, callback)
        callback({
          code = 1,
          stdout = "",
          stderr = "authentication failed",
        })

        return {}
      end

      local _, result = run_and_wait("test")

      assert.is_nil(result.output)
      assert.are.equal("authentication failed", result.err)
      assert.are.equal("codex", result.backend)
    end)
  end)

  it("does not load CodeCompanion for one-shot requests", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "codex"))

      stub_config(root, "codex")
      vim.env.PATH = bin

      package.loaded.codecompanion = nil

      vim.system = function(_, _, callback)
        callback({
          code = 0,
          stdout = vim.json.encode({
            type = "item.completed",
            item = {
              type = "agent_message",
              text = "LLM OK",
            },
          }),
          stderr = "",
        })

        return {}
      end

      local _, result = run_and_wait("test")

      assert.are.equal("LLM OK", result.output)
      assert.is_nil(package.loaded.codecompanion)
    end)
  end)

  it("does not wait synchronously for the provider", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "codex"))

      stub_config(root, "codex")
      vim.env.PATH = bin

      local provider_callback
      local callback_called = false

      local expected_handle = {
        kill = function() end,
      }

      vim.system = function(_, _, callback)
        provider_callback = callback
        return expected_handle
      end

      local handle = llm.run_structured("test", function()
        callback_called = true
      end)

      -- run_structured() must return while the provider is still running.
      assert.are.equal(expected_handle, handle)
      assert.is_false(callback_called)
      assert.is_function(provider_callback)

      provider_callback({
        code = 0,
        stdout = vim.json.encode({
          type = "item.completed",
          item = {
            type = "agent_message",
            text = "done",
          },
        }),
        stderr = "",
      })

      assert.is_true(vim.wait(1000, function()
        return callback_called
      end, 10))
    end)
  end)

  it("preserves meaningful whitespace in Claude output", function()
    with_tmpdir(function(tmp)
      local root = mkdir(vim.fs.joinpath(tmp, "project"))
      local bin = mkdir(vim.fs.joinpath(tmp, "bin"))

      make_executable(vim.fs.joinpath(bin, "claude"))

      stub_config(root, "claude")
      vim.env.PATH = bin

      vim.system = function(_, _, callback)
        callback({
          code = 0,
          stdout = "  replacement text  \n",
          stderr = "",
        })

        return {}
      end

      local _, result = run_and_wait("test")

      assert.are.equal("  replacement text  ", result.output)
      assert.is_nil(result.err)
    end)
  end)
end)

describe("llm selection replacement", function()
  local original_run_structured
  local original_input
  local original_select
  local buffers

  local function make_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(true, false)

    table.insert(buffers, bufnr)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)

    return bufnr
  end

  local function select_chars(bufnr, row, col, count)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, {
      row,
      col,
    })

    vim.cmd(string.format("normal! v%dl", count - 1))
  end

  before_each(function()
    original_run_structured = llm.run_structured
    original_input = vim.ui.input
    original_select = vim.ui.select
    buffers = {}
  end)

  after_each(function()
    llm.run_structured = original_run_structured
    vim.ui.input = original_input
    vim.ui.select = original_select

    for _, bufnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, {
          force = true,
        })
      end
    end
  end)

  it("does not modify the buffer before explicit acceptance", function()
    local bufnr = make_buffer({
      "abc def ghi",
    })

    select_chars(bufnr, 1, 4, 3)

    local decision
    local captured_prompt

    vim.ui.input = function(_, callback)
      callback("uppercase it")
    end

    llm.run_structured = function(prompt, callback)
      captured_prompt = prompt
      callback("DEF", nil, "codex")
      return {}
    end

    vim.ui.select = function(_, _, callback)
      decision = callback
    end

    llm.replace_selection()

    assert.are.same({
      "abc def ghi",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    assert.matches("uppercase it", captured_prompt, 1, true)
    assert.matches("def", captured_prompt, 1, true)
    assert.is_function(decision)

    decision("Apply", 1)

    assert.are.same({
      "abc DEF ghi",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("leaves the buffer untouched when replacement is rejected", function()
    local bufnr = make_buffer({
      "abc def ghi",
    })

    select_chars(bufnr, 1, 4, 3)

    vim.ui.input = function(_, callback)
      callback("uppercase it")
    end

    llm.run_structured = function(_, callback)
      callback("DEF", nil, "codex")
      return {}
    end

    vim.ui.select = function(_, _, callback)
      callback("Reject", 2)
    end

    llm.replace_selection()

    assert.are.same({
      "abc def ghi",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("does not overwrite a buffer changed while the request is running", function()
    local bufnr = make_buffer({
      "abc def ghi",
    })

    select_chars(bufnr, 1, 4, 3)

    local provider_callback
    local previewed = false

    vim.ui.input = function(_, callback)
      callback("uppercase it")
    end

    llm.run_structured = function(_, callback)
      provider_callback = callback
      return {}
    end

    vim.ui.select = function()
      previewed = true
    end

    llm.replace_selection()

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "changed by user",
    })

    provider_callback("DEF", nil, "codex")

    assert.is_false(previewed)
    assert.are.same({
      "changed by user",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("never edits the current buffer instead of the captured source buffer", function()
    local source = make_buffer({
      "abc def ghi",
    })

    select_chars(source, 1, 4, 3)

    local provider_callback

    vim.ui.input = function(_, callback)
      callback("uppercase it")
    end

    llm.run_structured = function(_, callback)
      provider_callback = callback
      return {}
    end

    llm.replace_selection()

    local other = make_buffer({
      "do not touch",
    })

    vim.ui.select = function(_, _, callback)
      callback("Apply", 1)
    end

    provider_callback("DEF", nil, "codex")

    assert.are.same({
      "abc DEF ghi",
    }, vim.api.nvim_buf_get_lines(source, 0, -1, false))

    assert.are.same({
      "do not touch",
    }, vim.api.nvim_buf_get_lines(other, 0, -1, false))
  end)

  it("leaves the selection untouched when the provider fails", function()
    local bufnr = make_buffer({
      "abc def ghi",
    })

    select_chars(bufnr, 1, 4, 3)

    local previewed = false

    vim.ui.input = function(_, callback)
      callback("uppercase it")
    end

    llm.run_structured = function(_, callback)
      callback(nil, "provider failed", "codex")
      return {}
    end

    vim.ui.select = function()
      previewed = true
    end

    llm.replace_selection()

    assert.is_false(previewed)
    assert.are.same({
      "abc def ghi",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("replaces complete linewise selections", function()
    local bufnr = make_buffer({
      "one",
      "two",
      "three",
    })

    vim.api.nvim_win_set_cursor(0, {
      2,
      0,
    })
    vim.cmd("normal! V")

    vim.ui.input = function(_, callback)
      callback("expand it")
    end

    llm.run_structured = function(_, callback)
      callback("TWO\nextra", nil, "codex")
      return {}
    end

    vim.ui.select = function(_, _, callback)
      callback("Apply", 1)
    end

    llm.replace_selection()

    assert.are.same({
      "one",
      "TWO",
      "extra",
      "three",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)
end)

describe("llm scratch buffers", function()
  local original_run_structured
  local original_input
  local source_bufnr
  local source_winid

  local function scratch_buffers()
    return vim
      .iter(vim.api.nvim_list_bufs())
      :filter(function(bufnr)
        return vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].llm_scratch == true
      end)
      :totable()
  end

  local function close_scratch_windows()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      local bufnr = vim.api.nvim_win_get_buf(winid)

      if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].llm_scratch == true and #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(winid, true)
      end
    end
  end

  local function delete_scratch_buffers()
    for _, bufnr in ipairs(scratch_buffers()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, {
          force = true,
        })
      end
    end
  end

  before_each(function()
    original_run_structured = llm.run_structured
    original_input = vim.ui.input

    source_bufnr = vim.api.nvim_create_buf(true, false)

    vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, {
      "source buffer",
    })

    vim.api.nvim_set_current_buf(source_bufnr)
    source_winid = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    llm.run_structured = original_run_structured
    vim.ui.input = original_input

    close_scratch_windows()
    delete_scratch_buffers()

    if
      source_winid
      and vim.api.nvim_win_is_valid(source_winid)
      and source_bufnr
      and vim.api.nvim_buf_is_valid(source_bufnr)
    then
      vim.api.nvim_set_current_win(source_winid)
      vim.api.nvim_win_set_buf(source_winid, source_bufnr)
    end

    if source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
      vim.api.nvim_buf_delete(source_bufnr, {
        force = true,
      })
    end
  end)

  it("shows a running scratch buffer until the provider responds", function()
    local provider_callback

    vim.ui.input = function(_, callback)
      callback("generate something")
    end

    llm.run_structured = function(_, callback)
      provider_callback = callback

      return {
        kill = function() end,
      }
    end

    llm.scratch()

    local buffers = scratch_buffers()

    assert.are.equal(1, #buffers)

    local bufnr = buffers[1]

    assert.are.equal(bufnr, vim.api.nvim_get_current_buf())
    assert.are.equal("running", vim.b[bufnr].llm_scratch_state)
    assert.is_false(vim.bo[bufnr].modifiable)
    assert.is_false(vim.bo[bufnr].modified)

    assert.are.same({
      "Generating LLM scratch…",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    assert.is_function(provider_callback)

    provider_callback("generated content", nil, "codex")

    assert.are.equal("ready", vim.b[bufnr].llm_scratch_state)
    assert.is_true(vim.bo[bufnr].modifiable)
    assert.is_true(vim.bo[bufnr].modified)

    assert.are.same({
      "generated content",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("creates an unnamed writable scratch buffer", function()
    vim.ui.input = function(_, callback)
      callback("generate something")
    end

    llm.run_structured = function(_, callback)
      callback("generated content", nil, "claude")

      return {}
    end

    llm.scratch()

    local buffers = scratch_buffers()

    assert.are.equal(1, #buffers)

    local bufnr = buffers[1]

    assert.are.equal("", vim.api.nvim_buf_get_name(bufnr))

    assert.are.equal("", vim.bo[bufnr].buftype)

    assert.is_true(vim.bo[bufnr].modifiable)

    assert.is_false(vim.bo[bufnr].swapfile)

    assert.is_true(vim.bo[bufnr].modified)

    assert.are.equal(0, vim.fn.buflisted(bufnr))

    assert.is_true(vim.b[bufnr].llm_scratch)

    assert.are.equal("claude", vim.b[bufnr].llm_backend)

    assert.are.equal("generate something", vim.b[bufnr].llm_request)

    assert.are.equal("ready", vim.b[bufnr].llm_scratch_state)
  end)

  it("does not modify the source buffer", function()
    vim.ui.input = function(_, callback)
      callback("generate something")
    end

    llm.run_structured = function(_, callback)
      callback("completely different content", nil, "codex")

      return {}
    end

    llm.scratch()

    assert.are.same({
      "source buffer",
    }, vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false))
  end)

  it("preserves provider output exactly", function()
    vim.ui.input = function(_, callback)
      callback("generate indented text")
    end

    llm.run_structured = function(_, callback)
      callback("  first line  \n    second line", nil, "codex")

      return {}
    end

    llm.scratch()

    local buffers = scratch_buffers()

    assert.are.equal(1, #buffers)

    assert.are.same({
      "  first line  ",
      "    second line",
    }, vim.api.nvim_buf_get_lines(buffers[1], 0, -1, false))
  end)

  it("shows provider failures in the scratch buffer", function()
    vim.ui.input = function(_, callback)
      callback("generate something")
    end

    llm.run_structured = function(_, callback)
      callback(nil, "provider failed", "codex")

      return {}
    end

    llm.scratch()

    local buffers = scratch_buffers()

    assert.are.equal(1, #buffers)

    local bufnr = buffers[1]

    assert.are.equal("failed", vim.b[bufnr].llm_scratch_state)
    assert.are.equal("codex", vim.b[bufnr].llm_backend)
    assert.is_true(vim.bo[bufnr].modifiable)
    assert.is_false(vim.bo[bufnr].modified)

    assert.are.same({
      "LLM scratch [codex] failed:",
      "",
      "provider failed",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("does not invoke the provider when the prompt is cancelled", function()
    local called = false

    vim.ui.input = function(_, callback)
      callback(nil)
    end

    llm.run_structured = function()
      called = true
    end

    llm.scratch()

    assert.is_false(called)

    assert.are.same({}, scratch_buffers())
  end)

  it("does not invoke the provider for an empty prompt", function()
    local called = false

    vim.ui.input = function(_, callback)
      callback("   ")
    end

    llm.run_structured = function()
      called = true
    end

    llm.scratch()

    assert.is_false(called)

    assert.are.same({}, scratch_buffers())
  end)

  it("supports a request passed directly without opening the prompt", function()
    local input_opened = false
    local captured_prompt

    vim.ui.input = function()
      input_opened = true
    end

    llm.run_structured = function(prompt, callback)
      captured_prompt = prompt

      callback("generated content", nil, "codex")

      return {}
    end

    llm.scratch("write a helper")

    assert.is_false(input_opened)

    assert.matches("write a helper", captured_prompt, 1, true)

    assert.are.equal(1, #scratch_buffers())
  end)

  it("does not send source-buffer contents implicitly", function()
    vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, {
      "SECRET_SOURCE_CONTENT",
    })

    local captured_prompt

    vim.ui.input = function(_, callback)
      callback("generate something")
    end

    llm.run_structured = function(prompt, callback)
      captured_prompt = prompt

      callback("generated content", nil, "codex")

      return {}
    end

    llm.scratch()

    assert.is_false(captured_prompt:find("SECRET_SOURCE_CONTENT", 1, true) ~= nil)
  end)
end)
