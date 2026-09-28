local function append_config_overrides(args, overrides)
  for _, value in ipairs(overrides) do
    args[#args + 1] = "-c"
    args[#args + 1] = value
  end
end

local codex_structured_args = {
  "--sandbox",
  "read-only",
  "--ask-for-approval",
  "never",
}

-- Match Codex's own isolated structured-request model: no shell, MCP,
-- plugins, skills, web access, subagents, hidden memories, or other
-- environment-backed tools. Neovim explicitly supplies all context.
append_config_overrides(codex_structured_args, {
  "features.apps=false",
  "features.code_mode=false",
  "features.code_mode_only=false",
  "features.context_management=false",
  "features.current_time_reminder=false",
  "features.deferred_executor=false",
  "features.enable_fanout=false",
  "features.goals=false",
  "features.hooks=false",
  "features.image_generation=false",
  "features.memories=false",
  "features.multi_agent=false",
  "features.multi_agent_v2=false",
  "features.plugins=false",
  "features.request_permissions_tool=false",
  "features.shell_snapshot=false",
  "features.shell_tool=false",
  "features.standalone_web_search=false",
  "features.token_budget=false",
  "features.tool_suggest=false",
  "features.unified_exec=false",
  "features.view_image=false",
  "cloud.skills.enabled=false",
  "skills.include_instructions=false",
  "tools.experimental_request_user_input.enabled=false",
  "tools.update_plan.enabled=false",
  'web_search="disabled"',
  "mcp_servers={}",
})

vim.list_extend(codex_structured_args, {
  "exec",
  "--ephemeral",
  "--ignore-user-config",
  "--ignore-rules",
  "--skip-git-repo-check",
  "--json",
  "-",
})

return {
  codex = {
    agent = "codex",
    command = "codex",
    description = "OpenAI Codex CLI",

    args = {
      "--sandbox",
      "read-only",
      "--ask-for-approval",
      "never",
    },

    structured_args = codex_structured_args,
    structured_output = "codex-jsonl",
  },

  claude = {
    agent = "claude_code",
    command = "claude",
    description = "Claude Code CLI",

    args = {
      "--permission-mode",
      "dontAsk",
    },

    structured_args = {
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
    },

    structured_output = "text",
  },
}
