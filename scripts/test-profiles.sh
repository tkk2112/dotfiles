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
      and .llmConfig.runtimes == ["mlx", "llama_cpp"]
      and .llmConfig.features == ["completion"]
    ' "$data_file" >/dev/null \
      || fail "default LLM capabilities did not resolve correctly"
  else
    jq -e '
      .llmConfig.providers == []
      and .llmConfig.runtimes == []
      and .llmConfig.features == []
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

  completion_service="$(
    jq -r '.llm.defaults.completion // empty' "$data_file"
  )"

  [ -n "$completion_service" ] \
    || fail "llm completion default is missing"

  jq -e --arg service "$completion_service" '
    .llm.services[$service] as $service_config
    |
      $service_config != null
      and $service_config.enabled == true
      and $service_config.type == "completion"
      and any(
        .llm.models[];
        .id == $service_config.model
        and .type == "completion"
        and .backends[$service_config.backend] != null
      )
  ' "$data_file" >/dev/null \
    || fail "llm completion default does not resolve to a valid completion service"

  jq -e '
    .llm.models[]
    | select(.id == "qwen2.5-coder-3b")
    | .name == "Qwen 2.5 Coder 3B"
      and .type == "completion"
      and .ctx_size == 32768
      and .backends.llama_cpp.model == "bartowski/Qwen2.5-Coder-3B-GGUF:Q4_K_M"
      and .backends.mlx.model == "mlx-community/Qwen2.5-Coder-3B-4bit"
  ' "$data_file" >/dev/null \
    || fail "llm model catalog did not resolve correctly"

  DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    run chezmoi --config "$config_file" execute-template \
    <"$repo_root/home/dot_local/bin/executable_dotfiles-llm-launch.tmpl" \
    >"$output"

  [ -s "$output" ] \
    || fail "llm launcher rendered empty"

  grep -Fq 'inline)' "$output" \
    || fail "llm launcher is missing inline service"

  grep -Fq 'BACKEND="llama_cpp"' "$output" \
    || fail "llm launcher did not resolve llama_cpp"

  grep -Fq 'PORT="18080"' "$output" \
    || fail "llm launcher did not resolve service port"

  grep -Fq 'CTX_SIZE="32768"' "$output" \
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

  printf '\n==> Testing custom LLM capabilities\n'

  DOTFILES_CI=true \
    DOTFILES_PROFILES="$profiles" \
    DOTFILES_LLM_PROVIDERS="codex" \
    DOTFILES_LLM_RUNTIMES="mlx" \
    DOTFILES_LLM_FEATURES="completion,laya" \
    run chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults

  chezmoi --config "$config_file" data >"$data_file"

  jq -e '
    .llmConfig.providers == ["codex"]
    and .llmConfig.runtimes == ["mlx"]
    and .llmConfig.features == ["completion", "laya"]
  ' "$data_file" >/dev/null \
    || fail "custom LLM capabilities did not resolve correctly"
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

test_invalid_llm_runtime() {
  config_file="$test_root/invalid-llm-runtime.toml"
  output="$test_root/invalid-llm-runtime.log"

  printf '\n==> Rejecting invalid LLM runtime\n'

  if DOTFILES_CI=true \
    DOTFILES_PROFILES="workstation,development,llm" \
    DOTFILES_LLM_RUNTIMES="mlx,magic" \
    chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults \
    >"$output" 2>&1; then
    cat "$output"
    fail "invalid LLM runtime was accepted"
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
  test_invalid_llm_provider
  test_invalid_llm_runtime
  test_invalid_llm_feature
fi

if [ "$(uname -s)" != "Darwin" ]; then
  printf '%s\n' "$NON_DARWIN_INVALID_PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
    test_invalid_profile_set "$profiles"
  done
fi

printf '%s\n' "$INVALID_PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
  test_invalid_profile_set "$profiles"
done
