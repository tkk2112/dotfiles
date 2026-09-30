#!/bin/sh
set -eu

VALID_PROFILE_SETS="
workstation
workstation,development
workstation,laptop,development,owned
headless
headless,server,owned
workstation,development,gaming,server,owned
"

DARWIN_VALID_PROFILE_SETS="
workstation,development,llm
"

NON_DARWIN_INVALID_PROFILE_SETS="
workstation,development,llm
"

INVALID_PROFILE_SETS="
development
llm
workstation,headless
workstation,unknown
workstation,workstation
"

repo_root="${DOTFILES_LOCATION:-$(git rev-parse --show-toplevel)}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

profile_slug() {
  printf '%s' "$1" | tr ',' '-'
}

contains_profile() {
  profiles="$1"
  expected="$2"

  case ",$profiles," in
    *",$expected,"*) return 0 ;;
    *) return 1 ;;
  esac
}

test_tmux_profile() {
  profiles="$1"
  config_file="$2"
  slug="$(profile_slug "$profiles")"
  output="$test_root/tmux-$slug.conf"

  DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    run chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_config/tmux/tmux.conf.tmpl" \
    >"$output"

  if contains_profile "$profiles" laptop; then
    grep -Fq "tmux-plugins/tmux-battery" "$output" \
      || fail "laptop profile did not enable tmux-battery"
    grep -Fq '#{battery_percentage}' "$output" \
      || fail "laptop profile did not enable the battery widget"
  else
    if grep -Fq "tmux-plugins/tmux-battery" "$output"; then
      fail "non-laptop profile enabled tmux-battery"
    fi
    if grep -Fq '#{battery_percentage}' "$output"; then
      fail "non-laptop profile enabled the battery widget"
    fi
  fi
}

test_llm_capability_defaults() {
  profiles="$1"
  data_file="$2"

  if contains_profile "$profiles" llm; then
    jq -e '
      .llmConfig.providers == ["codex", "claude"]
      and .llmConfig.engines == ["mlx", "llama_cpp"]
      and .llmConfig.features == ["completion"]
      and .llmConfig.disabledRuntimes == []
      and .llmConfig.manualRuntimes == []
    ' "$data_file" >/dev/null \
      || fail "default LLM capabilities did not resolve correctly"
  else
    jq -e '
      .llmConfig.providers == []
      and .llmConfig.engines == []
      and .llmConfig.features == []
      and .llmConfig.disabledRuntimes == []
      and .llmConfig.manualRuntimes == []
    ' "$data_file" >/dev/null \
      || fail "non-LLM profile contains LLM capabilities"
  fi
}

test_llm_profile() {
  profiles="$1"
  config_file="$2"
  data_file="$3"
  slug="$(profile_slug "$profiles")"
  output="$test_root/llm-launch-$slug"

  if ! contains_profile "$profiles" llm; then
    return 0
  fi

  completion_runtime="$(
    jq -r '.llm.defaults.completion // empty' "$data_file"
  )"

  [ -n "$completion_runtime" ] \
    || fail "llm completion default is missing"

  jq -e --arg runtime "$completion_runtime" '
    .llm.runtimes[$runtime] as $runtime_config
    |
      $runtime_config != null
      and $runtime_config.feature == "completion"
      and $runtime_config.model != null
      and any(
        .llm.models[];
        .id == $runtime_config.model
        and .kind == "generative"
        and (.engines | length) > 0
      )
  ' "$data_file" >/dev/null \
    || fail "llm completion default does not resolve to a valid completion runtime"

  jq -e '
    .llm.models[]
    | select(.id == "qwen2.5-coder-3b")
    | .name == "Qwen 2.5 Coder 3B"
      and .kind == "generative"
      and .context == 32768
      and .engines.llama_cpp.model == "bartowski/Qwen2.5-Coder-3B-GGUF:Q4_K_M"
      and .engines.mlx.model == "mlx-community/Qwen2.5-Coder-3B-4bit"
  ' "$data_file" >/dev/null \
    || fail "llm model catalog did not resolve correctly"

  DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    run chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_local/bin/executable_dotfiles-llm-launch.tmpl" \
    >"$output"

  [ -s "$output" ] \
    || fail "llm launcher rendered empty"

  grep -Fq 'completion)' "$output" \
    || fail "llm launcher is missing inline service"

  grep -Fq 'ENGINE="llama_cpp"' "$output" \
    || fail "llm launcher did not resolve llama_cpp"

  grep -Fq 'PORT="18080"' "$output" \
    || fail "llm launcher did not resolve service port"

  grep -Fq 'CONTEXT="32768"' "$output" \
    || fail "llm launcher did not resolve context size"

  grep -Fq -- '--host 127.0.0.1' "$output" \
    || fail "llm launcher is not loopback-only"

  grep -Fq -- '--no-agent' "$output" \
    || fail "llm launcher does not disable agent mode"

  grep -Fq -- '--no-webui' "$output" \
    || fail "llm launcher does not disable the web UI"
}

test_llm_capability_selection() {
  profiles="workstation,development,llm"
  config_file="$test_root/llm-capabilities.toml"
  data_file="$test_root/llm-capabilities.json"
  packages_output="$test_root/llm-capabilities-packages"
  uv_output="$test_root/llm-capabilities-uv"
  launcher_output="$test_root/llm-capabilities-launcher"
  completion_output="$test_root/llm-capabilities-completion.lua"
  capabilities_output="$test_root/llm-capabilities.lua"

  printf '\n==> Testing custom LLM capabilities\n'

  DOTFILES_CI=true \
    DOTFILES_PROFILES="$profiles" \
    DOTFILES_LLM_PROVIDERS="codex" \
    DOTFILES_LLM_ENGINES="mlx" \
    DOTFILES_LLM_FEATURES="completion,laya" \
    run chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults

  chezmoi --config "$config_file" data >"$data_file"

  jq -e '
    .llmConfig.providers == ["codex"]
    and .llmConfig.engines == ["mlx"]
    and .llmConfig.features == ["completion", "laya"]
  ' "$data_file" >/dev/null \
    || fail "custom LLM capabilities did not resolve correctly"

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_config/nvim/lua/config/llm/capabilities.lua.tmpl" \
    >"$capabilities_output"

  grep -Fq '"codex"' "$capabilities_output" \
    || fail "Neovim capabilities did not include Codex"

  if grep -Fq '"claude"' "$capabilities_output"; then
    fail "Neovim capabilities included unselected Claude provider"
  fi

  grep -Fq '"mlx"' "$capabilities_output" \
    || fail "Neovim capabilities did not include MLX engine"

  grep -Fq '"completion"' "$capabilities_output" \
    || fail "Neovim capabilities did not include completion feature"

  grep -Fq '"laya"' "$capabilities_output" \
    || fail "Neovim capabilities did not include Laya feature"

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/.chezmoiscripts/run_onchange_after_05-packages.sh.tmpl" \
    >"$packages_output"

  grep -Fq 'codex' "$packages_output" \
    || fail "Codex provider did not select Codex package"

  if grep -Fq 'claude-code@latest' "$packages_output"; then
    fail "unselected Claude provider selected Claude package"
  fi

  grep -Fq 'mlx-lm' "$packages_output" \
    || fail "MLX engine did not select mlx-lm package"

  if grep -Fq 'llama.cpp' "$packages_output"; then
    fail "unselected llama_cpp engine selected llama.cpp package"
  fi

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/.chezmoiscripts/run_onchange_after_35-uv-tools.sh.tmpl" \
    >"$uv_output"

  grep -Fq 'laya-mlx|laya-mlx' "$uv_output" \
    || fail "Laya feature did not select laya-mlx uv tool"

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_local/bin/executable_dotfiles-llm-launch.tmpl" \
    >"$launcher_output"

  grep -Fq 'ENGINE="mlx"' "$launcher_output" \
    || fail "single selected MLX engine was not used by completion service"

  grep -Fq 'MODEL="mlx-community/Qwen2.5-Coder-3B-4bit"' "$launcher_output" \
    || fail "MLX completion model did not resolve correctly"

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_config/nvim/lua/config/llm/local.lua.tmpl" \
    >"$completion_output"

  grep -Fq 'enabled = true' "$completion_output" \
    || fail "completion feature did not enable local completion"

  grep -Fq 'engine = "mlx"' "$completion_output" \
    || fail "local completion did not resolve MLX engine"

  grep -Fq 'model = "mlx-community/Qwen2.5-Coder-3B-4bit"' "$completion_output" \
    || fail "local completion did not resolve MLX model"
}

test_llm_without_completion() {
  profiles="workstation,development,llm"
  config_file="$test_root/llm-no-completion.toml"
  launcher_output="$test_root/llm-no-completion-launcher"
  completion_output="$test_root/llm-no-completion.lua"

  printf '\n==> Testing LLM without local completion\n'

  DOTFILES_CI=true \
    DOTFILES_PROFILES="$profiles" \
    DOTFILES_LLM_PROVIDERS="codex" \
    DOTFILES_LLM_ENGINES="mlx" \
    DOTFILES_LLM_FEATURES="laya" \
    run chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_local/bin/executable_dotfiles-llm-launch.tmpl" \
    >"$launcher_output"

  if grep -Fq 'completion)' "$launcher_output"; then
    fail "disabled completion feature still generated completion runtime"
  fi

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_config/nvim/lua/config/llm/local.lua.tmpl" \
    >"$completion_output"

  grep -Fq 'enabled = false' "$completion_output" \
    || fail "disabled completion feature still enabled local completion"
}

test_invalid_llm_provider() {
  config_file="$test_root/invalid-llm-provider.toml"
  output="$test_root/invalid-llm-provider.log"

  printf '\n==> Rejecting invalid LLM provider\n'

  if DOTFILES_CI=true \
    DOTFILES_PROFILES="workstation,development,llm" \
    DOTFILES_LLM_PROVIDERS="codex,skynet" \
    chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults \
    >"$output" 2>&1; then
    cat "$output"
    fail "invalid LLM provider was accepted"
  fi
}

test_invalid_llm_engine() {
  config_file="$test_root/invalid-llm-engine.toml"
  output="$test_root/invalid-llm-engine.log"

  printf '\n==> Rejecting invalid LLM engine\n'

  if DOTFILES_CI=true \
    DOTFILES_PROFILES="workstation,development,llm" \
    DOTFILES_LLM_ENGINES="mlx,magic" \
    chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults \
    >"$output" 2>&1; then
    cat "$output"
    fail "invalid LLM engine was accepted"
  fi
}

test_invalid_llm_feature() {
  config_file="$test_root/invalid-llm-feature.toml"
  output="$test_root/invalid-llm-feature.log"

  printf '\n==> Rejecting invalid LLM feature\n'

  if DOTFILES_CI=true \
    DOTFILES_PROFILES="workstation,development,llm" \
    DOTFILES_LLM_FEATURES="completion,telepathy" \
    chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults \
    >"$output" 2>&1; then
    cat "$output"
    fail "invalid LLM feature was accepted"
  fi
}

test_llm_runtime_overrides() {
  profiles="workstation,development,llm"
  config_file="$test_root/llm-runtime-overrides.toml"
  data_file="$test_root/llm-runtime-overrides.json"
  runtime_script="$test_root/llm-runtime-overrides-runtime-script"
  completion_output="$test_root/llm-runtime-overrides-completion.lua"

  printf '\n==> Testing LLM runtime overrides\n'

  DOTFILES_CI=true \
    DOTFILES_PROFILES="$profiles" \
    DOTFILES_LLM_PROVIDERS="codex" \
    DOTFILES_LLM_ENGINES="mlx" \
    DOTFILES_LLM_FEATURES="completion" \
    DOTFILES_LLM_MANUAL_RUNTIMES="completion" \
    run chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults

  chezmoi --config "$config_file" data >"$data_file"

  jq -e '
    .llmConfig.manualRuntimes == ["completion"]
    and .llmConfig.disabledRuntimes == []
  ' "$data_file" >/dev/null \
    || fail "manual runtime override did not resolve"

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/.chezmoiscripts/run_onchange_after_45-llm-runtimes.sh.tmpl" \
    >"$runtime_script"

  grep -Fq 'install_runtime "completion" "false"' "$runtime_script" \
    || fail "manual completion runtime still autostarts"

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_config/nvim/lua/config/llm/local.lua.tmpl" \
    >"$completion_output"

  grep -Fq 'enabled = true' "$completion_output" \
    || fail "manual completion runtime was not enabled"

  grep -Fq 'autostart = false' "$completion_output" \
    || fail "manual completion runtime still autostarts"

  config_file="$test_root/llm-disabled-runtime.toml"
  completion_output="$test_root/llm-disabled-runtime-completion.lua"

  DOTFILES_CI=true \
    DOTFILES_PROFILES="$profiles" \
    DOTFILES_LLM_PROVIDERS="codex" \
    DOTFILES_LLM_ENGINES="mlx" \
    DOTFILES_LLM_FEATURES="completion" \
    DOTFILES_LLM_DISABLED_RUNTIMES="completion" \
    run chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults

  chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_config/nvim/lua/config/llm/local.lua.tmpl" \
    >"$completion_output"

  grep -Fq 'enabled = false' "$completion_output" \
    || fail "disabled completion runtime remained enabled"
}

test_profile_set() {
  profiles="$1"
  slug="$(profile_slug "$profiles")"
  config_file="$test_root/$slug.toml"
  destination="$test_root/$slug-home"

  printf '\n==> Testing profiles: %s\n' "$profiles"

  DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    run chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults

  data_file="$test_root/$slug-data.json"
  chezmoi --config "$config_file" data >"$data_file"

  actual_profiles="$(jq -r '.profiles | join(",")' "$data_file")"

  if jq -e 'has("hasRoot") or has("base")' "$data_file" >/dev/null; then
    fail "legacy profile flags are still present for: $profiles"
  fi

  if [ "$actual_profiles" != "$profiles" ]; then
    fail "profile mismatch: expected '$profiles', got '$actual_profiles'"
  fi

  test_llm_capability_defaults "$profiles" "$data_file"

  run chezmoi --config "$config_file" \
    --source "$repo_root" \
    --destination "$destination" \
    apply --dry-run --exclude scripts,encrypted

  for script in "$repo_root"/home/.chezmoiscripts/*.tmpl; do
    output="$test_root/$(basename "$script" .tmpl)-$slug"

    DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
      run chezmoi --config "$config_file" execute-template \
      <"$script" \
      >"$output"

    run sh -n "$output"
  done

  test_tmux_profile "$profiles" "$config_file"
  test_llm_profile "$profiles" "$config_file" "$data_file"
}

test_invalid_profile_set() {
  profiles="$1"
  slug="invalid-$(profile_slug "$profiles")"
  config_file="$test_root/$slug.toml"
  output="$test_root/$slug.log"

  printf '\n==> Rejecting invalid profiles: %s\n' "$profiles"

  if DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults \
    >"$output" 2>&1; then
    cat "$output"
    fail "invalid profile set was accepted: $profiles"
  fi
}

command -v chezmoi >/dev/null 2>&1 || fail "missing command: chezmoi"
command -v jq >/dev/null 2>&1 || fail "missing command: jq"

printf '%s\n' "$VALID_PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
  test_profile_set "$profiles"
done

if [ "$(uname -s)" = "Darwin" ]; then
  printf '%s\n' "$DARWIN_VALID_PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
    test_profile_set "$profiles"
  done

  test_llm_capability_selection
  test_llm_without_completion
  test_invalid_llm_provider
  test_invalid_llm_engine
  test_invalid_llm_feature
  test_llm_runtime_overrides
fi

if [ "$(uname -s)" != "Darwin" ]; then
  printf '%s\n' "$NON_DARWIN_INVALID_PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
    test_invalid_profile_set "$profiles"
  done
fi

printf '%s\n' "$INVALID_PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
  test_invalid_profile_set "$profiles"
done
