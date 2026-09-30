#!/bin/sh
set -eu

repo_root="${DOTFILES_LOCATION:-$(git rev-parse --show-toplevel)}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'Skipping LLM config tests on non-Darwin host\n'
  exit 0
fi

profiles="workstation,development,llm"

new_config() {
  name="$1"
  config="$test_root/$name.toml"

  DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    chezmoi init \
    --config "$config" \
    --source "$repo_root" \
    --promptDefaults >/dev/null

  printf '%s\n' "$config"
}

expect_failure() {
  name="$1"
  config="$2"
  expected="$3"
  output="$test_root/$name.out"
  error="$test_root/$name.err"

  if DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    chezmoi --config "$config" execute-template \
    <"$repo_root/home/dot_local/bin/executable_dotfiles-llm-launch.tmpl" \
    >"$output" 2>"$error"; then
    fail "$name: invalid configuration was accepted"
  fi

  if ! grep -Fq "$expected" "$error"; then
    cat "$error" >&2
    fail "$name: expected error not found: $expected"
  fi

  printf 'PASS: %s\n' "$name"
}

config="$(new_config unknown-model)"
cat >>"$config" <<'EOF'

[data.llm.runtimes.completion]
model = "does-not-exist"
EOF

expect_failure \
  unknown-model \
  "$config" \
  "unknown LLM model does-not-exist for runtime completion"

config="$(new_config kind-mismatch)"
cat >>"$config" <<'EOF'

[data.llm.runtimes.completion]
model = "laya"
EOF

expect_failure \
  kind-mismatch \
  "$config" \
  "LLM runtime completion for feature completion requires model kind generative, got decision"

config="$(new_config unsupported-engine)"
cat >>"$config" <<'EOF'

[[data.llm.models]]
id = "unsupported-engine"
name = "Unsupported engine test model"
kind = "generative"
context = 32768

[data.llm.models.engines.magic]
model = "test/magic"

[data.llm.runtimes.completion]
model = "unsupported-engine"
EOF

expect_failure \
  unsupported-engine \
  "$config" \
  "LLM runtime completion model unsupported-engine has no selected supported engine"

config="$(new_config duplicate-port)"
cat >>"$config" <<'EOF'

[data.llm.runtimes.second]
feature = "completion"
model = "qwen2.5-coder-3b"
port = 18080
autostart = false
EOF

expect_failure \
  duplicate-port \
  "$config" \
  "use duplicate port 18080"
