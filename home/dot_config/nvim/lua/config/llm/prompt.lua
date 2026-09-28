local M = {}

local function instruction_prefix(config)
  if #config.instructions == 0 then
    return ""
  end

  local lines = {
    "Read and follow these project instruction files before answering:",
  }

  for _, path in ipairs(config.instructions) do
    table.insert(lines, "@" .. path)
  end

  return table.concat(lines, "\n")
end

function M.interactive(config, prompt)
  local prefix = instruction_prefix(config)

  if prefix == "" then
    return prompt
  end

  return prefix .. "\n\n" .. prompt
end

function M.structured(config, prompt)
  if #config.instructions == 0 then
    return prompt
  end

  local parts = {
    "Follow these project instructions before answering:",
  }

  for _, path in ipairs(config.instructions) do
    local ok, lines = pcall(vim.fn.readfile, path)

    if not ok then
      return nil, "Could not read LLM instruction file: " .. path
    end

    table.insert(parts, string.format("## %s\n%s", vim.fs.basename(path), table.concat(lines, "\n")))
  end

  table.insert(parts, prompt)

  return table.concat(parts, "\n\n")
end

return M
