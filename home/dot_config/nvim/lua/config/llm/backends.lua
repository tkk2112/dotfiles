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

    structured_args = {
      "--sandbox",
      "read-only",
      "--ask-for-approval",
      "never",
      "-c",
      'web_search="disabled"',
      "exec",
      "--ephemeral",
      "--ignore-user-config",
      "--ignore-rules",
      "--skip-git-repo-check",
      "--json",
      "-",
    },

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
