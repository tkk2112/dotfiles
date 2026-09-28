local M = {}

local function scratch_prompt(request)
  return table.concat({
    "Generate the requested scratch content.",
    "",
    "Return only the content that should appear in the scratch buffer.",
    "Do not explain the result unless the user explicitly asks for an explanation.",
    "Do not wrap the result in Markdown fences unless the user explicitly asks for Markdown fences.",
    "",
    "User request:",
    request,
  }, "\n")
end

local function split_output(output)
  if output == "" then
    return {}
  end

  return vim.split(output, "\n", {
    plain = true,
  })
end

local function open_scratch(output, backend_name, request)
  local bufnr = vim.api.nvim_create_buf(false, false)

  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false

  vim.b[bufnr].llm_scratch = true
  vim.b[bufnr].llm_backend = backend_name
  vim.b[bufnr].llm_request = request

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, split_output(output))

  -- Treat generated content as unsaved user-visible work. Closing it should
  -- require the normal Neovim confirmation rather than silently discarding it.
  vim.bo[bufnr].modified = true

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, bufnr)

  return bufnr
end

local function submit(run_structured, request)
  request = vim.trim(request or "")

  if request == "" then
    return nil
  end

  return run_structured(scratch_prompt(request), function(output, err, backend_name)
    if err then
      vim.notify(string.format("LLM scratch [%s] failed:\n%s", backend_name or "unknown", err), vim.log.levels.ERROR)
      return
    end

    open_scratch(output, backend_name, request)
  end)
end

function M.run(run_structured, request)
  if request and vim.trim(request) ~= "" then
    return submit(run_structured, request)
  end

  vim.ui.input({
    prompt = "LLM scratch: ",
  }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end

    submit(run_structured, input)
  end)

  return nil
end

return M
