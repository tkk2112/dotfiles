local M = {}

local state = {
  service = nil,
  endpoint = nil,
  autostart = true,

  available = false,
  checking = false,
  acquiring = false,
  acquired = false,

  checked_at = 0,
  check_interval_ms = 5000,

  generation = 0,
  lifecycle_error_notified = false,
  pid = tostring(vim.fn.getpid()),
}

local function now_ms()
  return vim.uv.hrtime() / 1e6
end

local function notify_lifecycle_error(message)
  if state.lifecycle_error_notified then
    return
  end

  state.lifecycle_error_notified = true

  vim.schedule(function()
    vim.notify(message, vim.log.levels.ERROR)
  end)
end

local function acquire_manual_service(generation)
  if state.autostart or state.acquiring or not state.service then
    return
  end

  state.acquiring = true

  vim.system({
    "dotfiles-llm",
    "acquire",
    state.service,
    state.pid,
  }, {
    text = true,
  }, function(result)
    if generation ~= state.generation then
      return
    end

    state.acquiring = false

    if result.code ~= 0 then
      notify_lifecycle_error(
        string.format("Failed acquiring LLM completion service %s:\n%s", state.service, vim.trim(result.stderr or ""))
      )

      return
    end

    state.acquired = true
    state.lifecycle_error_notified = false

    -- The server may still be loading its model. Force the next completion
    -- attempt to perform another health check.
    state.checked_at = 0
  end)
end

function M.refresh(force)
  if not state.endpoint or state.checking then
    return
  end

  local now = now_ms()

  if not force and now - state.checked_at < state.check_interval_ms then
    return
  end

  state.checked_at = now
  state.checking = true

  local generation = state.generation

  vim.system({
    "curl",
    "--silent",
    "--show-error",
    "--fail",
    "--connect-timeout",
    "0.2",
    "--max-time",
    "0.5",
    state.endpoint .. "/health",
  }, {
    text = true,
  }, function(result)
    if generation ~= state.generation then
      return
    end

    state.available = result.code == 0
    state.checking = false

    if not state.available then
      acquire_manual_service(generation)
    end
  end)
end

function M.available()
  M.refresh(false)
  return state.available
end

function M.stop()
  if state.autostart or not state.acquired or not state.service then
    return
  end

  local service = state.service
  local pid = state.pid

  state.acquired = false

  local process = vim.system({
    "dotfiles-llm",
    "release",
    service,
    pid,
  }, {
    text = true,
  })

  -- VimLeavePre is immediately followed by process termination, so wait
  -- briefly for the lease to be released.
  pcall(function()
    process:wait(1000)
  end)
end

function M.setup(opts)
  -- In practice setup runs once, but release any previous lease if the module
  -- is reconfigured during the same Neovim session.
  M.stop()

  state.generation = state.generation + 1

  state.service = assert(opts.service)
  state.endpoint = assert(opts.endpoint)
  state.autostart = opts.autostart == true

  state.available = false
  state.checking = false
  state.acquiring = false
  state.acquired = false

  state.checked_at = 0
  state.check_interval_ms = opts.check_interval_ms or 5000

  state.lifecycle_error_notified = false
  state.pid = tostring(vim.fn.getpid())

  local group = vim.api.nvim_create_augroup("LlmLocalCompletion", {
    clear = true,
  })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
      M.refresh(false)
    end,
    desc = "Activate local LLM completion",
  })

  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      M.refresh(false)
    end,
    desc = "Refresh local LLM completion availability",
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = M.stop,
    desc = "Release local LLM completion service",
  })

  if state.autostart then
    M.refresh(true)
  end
end

return M
