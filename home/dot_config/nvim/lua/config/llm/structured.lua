local M = {}

local backends = require("config.llm.backends")
local prompt = require("config.llm.prompt")

local function parse_text_output(stdout)
  local output = (stdout or ""):gsub("\r\n", "\n")

  -- claude -p writes a transport newline after the result. Remove that one
  -- newline, but preserve whitespace that belongs to the model response.
  if output:sub(-1) == "\n" then
    output = output:sub(1, -2)
  end

  if vim.trim(output) == "" then
    return nil, "LLM returned no output"
  end

  return output
end

local function parse_codex_jsonl(stdout)
  local response

  for line in (stdout or ""):gmatch("[^\r\n]+") do
    local ok, event = pcall(vim.json.decode, line)

    if
      ok
      and type(event) == "table"
      and event.type == "item.completed"
      and type(event.item) == "table"
      and event.item.type == "agent_message"
      and type(event.item.text) == "string"
    then
      response = event.item.text
    end
  end

  if not response or vim.trim(response) == "" then
    return nil, "Codex returned no final agent message"
  end

  return response
end

local function parse_output(backend, stdout)
  if backend.structured_output == "codex-jsonl" then
    return parse_codex_jsonl(stdout)
  end

  if backend.structured_output == "text" then
    return parse_text_output(stdout)
  end

  return nil, "Unknown LLM structured output format"
end

local function process_error(backend, result)
  local stderr = vim.trim(result.stderr or "")

  if stderr == "" then
    stderr = string.format("%s exited with code %s", backend.command, tostring(result.code))
  end

  if #stderr > 2000 then
    stderr = stderr:sub(1, 2000) .. "\n..."
  end

  return stderr
end

local function finish(callback, output, err, backend_name)
  if not callback then
    return
  end

  vim.schedule(function()
    callback(output, err, backend_name)
  end)
end

---@param config table
---@param backend_name string
---@param request string
---@param callback fun(output: string|nil, err: string|nil, backend: string|nil)
---@return table|nil process vim.system process handle when successfully started
function M.run(config, backend_name, request, callback)
  if type(request) ~= "string" or vim.trim(request) == "" then
    finish(callback, nil, "LLM request is empty", nil)
    return nil
  end

  if not config.project_root then
    finish(callback, nil, "LLM is only available inside a configured project", nil)
    return nil
  end

  if not config.enabled then
    finish(callback, nil, "LLM is disabled for this project scope", nil)
    return nil
  end

  local backend = backends[backend_name]

  if not backend or not backend.structured_args then
    finish(callback, nil, "No one-shot runner is configured for backend: " .. tostring(backend_name), backend_name)
    return nil
  end

  if vim.fn.executable(backend.command) ~= 1 then
    finish(callback, nil, "LLM backend is not available in PATH: " .. backend.command, backend_name)
    return nil
  end

  if not vim.system then
    finish(callback, nil, "This Neovim version does not provide vim.system()", backend_name)
    return nil
  end

  if not config.scope_root or vim.fn.isdirectory(config.scope_root) ~= 1 then
    finish(callback, nil, "LLM scope directory is unavailable: " .. tostring(config.scope_root), backend_name)
    return nil
  end

  local full_prompt, prompt_err = prompt.structured(config, request)

  if not full_prompt then
    finish(callback, nil, prompt_err, backend_name)
    return nil
  end

  local command = {
    backend.command,
  }

  vim.list_extend(command, vim.deepcopy(backend.structured_args))

  local ok, process = pcall(vim.system, command, {
    cwd = config.scope_root,
    stdin = full_prompt,
    text = true,
    timeout = 120000,
  }, function(result)
    if result.code ~= 0 then
      finish(callback, nil, process_error(backend, result), backend_name)
      return
    end

    local parse_ok, output, parse_err = pcall(parse_output, backend, result.stdout)

    if not parse_ok then
      finish(callback, nil, "Could not parse LLM output: " .. tostring(output), backend_name)
      return
    end

    if not output then
      finish(callback, nil, parse_err, backend_name)
      return
    end

    finish(callback, output, nil, backend_name)
  end)

  if not ok then
    finish(callback, nil, "Could not start LLM backend: " .. tostring(process), backend_name)
    return nil
  end

  return process
end

return M
