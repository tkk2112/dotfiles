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

[data.llm.services.inline]
model = "does-not-exist"
EOF

expect_failure \
  unknown-model \
  "$config" \
  "unknown LLM model does-not-exist for service inline"

config="$(new_config type-mismatch)"
cat >>"$config" <<'EOF'

[data.llm.services.inline]
type = "agent"
EOF

expect_failure \
  type-mismatch \
  "$config" \
  "LLM service inline has type agent but model qwen2.5-coder-3b has type completion"

config="$(new_config unsupported-backend)"
cat >>"$config" <<'EOF'

[[data.llm.models]]
id = "mlx-only"
name = "MLX-only test model"
type = "completion"
ctx_size = 32768

[data.llm.models.backends.mlx]
model = "test/mlx-only"

[data.llm.services.inline]
backend = "llama_cpp"
model = "mlx-only"
EOF

expect_failure \
  unsupported-backend \
  "$config" \
  "LLM model mlx-only does not support backend llama_cpp"

config="$(new_config unresolvable-backend)"
cat >>"$config" <<'EOF'

[data.llm.services.inline]
backend = "bogus"
EOF

expect_failure \
  unresolvable-backend \
  "$config" \
  'LLM completion service inline cannot resolve a runtime from ["mlx","llama_cpp"]'

config="$(new_config duplicate-port)"
cat >>"$config" <<'EOF'

[data.llm.services.second]
type = "completion"
enabled = true
autostart = false
backend = "mlx"
model = "qwen2.5-coder-3b"
port = 18080
EOF

expect_failure \
  duplicate-port \
  "$config" \
  "use duplicate port 18080"
