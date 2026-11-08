#!/bin/sh
# Render every chezmoi template for a set of machine configurations, dry-run
# apply them into a scratch home, and lint the rendered output: shell syntax, shellcheck, JSON/TOML/YAML/plist/Lua
# parsing, plus cross-file invariants that rendering alone does not catch.
set -eu

repo_root="${DOTFILES_LOCATION:-$(git rev-parse --show-toplevel)}"
source_root="$repo_root/home"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT INT TERM

# Constant conditions are expected once a template has been rendered.
SHELLCHECK_EXCLUDES="SC2050,SC2194"

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

die() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

skip() {
  printf 'SKIP: %s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

python_has() {
  have python3 && python3 -c "import $1" >/dev/null 2>&1
}

# name|profiles|ssh agent|extra env (space separated KEY=VALUE)
CONFIGURATIONS="
headless-server|headless,server,owned|none|
workstation|workstation,development,owned|omz|
workstation-proton|workstation,development,gaming,server,owned|proton-pass|
"

DARWIN_CONFIGURATIONS="
macos-llm-all|workstation,laptop,development,owned,llm|proton-pass|DOTFILES_LLM_PROVIDERS=codex,claude DOTFILES_LLM_ENGINES=mlx,llama_cpp,colibri DOTFILES_LLM_FEATURES=completion,laya,agent
macos-llm-local|workstation,laptop,development,owned,llm|none|DOTFILES_LLM_ENGINES=llama_cpp DOTFILES_LLM_FEATURES=completion DOTFILES_LLM_MANUAL_RUNTIMES=completion
"

init_config() {
  name="$1"
  profiles="$2"
  ssh_agent="$3"
  extra_env="$4"
  config="$test_root/$name.toml"

  # shellcheck disable=SC2086 # extra_env is a list of KEY=VALUE words
  env DOTFILES_CI=true DOTFILES_PROFILES="$profiles" $extra_env \
    chezmoi init \
    --config "$config" \
    --source "$repo_root" \
    --promptDefaults \
    --promptChoice "SSH agent=$ssh_agent" \
    >"$test_root/$name.init.log" 2>&1 || {
    cat "$test_root/$name.init.log" >&2
    die "$name: chezmoi init failed"
  }

  printf '%s\n' "$config"
}

render() {
  config="$1"
  template="$2"
  output="$3"

  mkdir -p "$(dirname "$output")"

  if ! DOTFILES_CI=true chezmoi --config "$config" --source "$repo_root" \
    execute-template <"$template" >"$output" 2>"$output.err"; then
    cat "$output.err" >&2
    fail "render failed: ${template#"$repo_root"/}"
    return 1
  fi
}

shell_of() {
  first_line="$(sed -n '1p' "$1")"

  case "$first_line" in
    '#!/bin/sh'* | '#!/usr/bin/env sh'*) printf 'sh\n' ;;
    '#!/bin/bash'* | '#!/usr/bin/env bash'*) printf 'bash\n' ;;
    '#!/bin/zsh'* | '#!/usr/bin/env zsh'*) printf 'zsh\n' ;;
    '#!'*) printf 'other\n' ;;
    *) printf 'none\n' ;;
  esac
}

lint_shell() {
  file="$1"
  shell="$2"
  label="$3"

  case "$shell" in
    sh | bash)
      "$shell" -n "$file" || {
        fail "$label: $shell syntax"
        return 0
      }

      if have shellcheck; then
        shellcheck -S warning -e "$SHELLCHECK_EXCLUDES" -s "$shell" "$file" \
          || fail "$label: shellcheck"
      fi
      ;;
    zsh)
      if have zsh; then
        zsh -n "$file" || fail "$label: zsh syntax"
      fi
      ;;
  esac
}

lint_rendered() {
  file="$1"
  template="$2"
  label="$3"

  # chezmoi does not create targets whose rendered content is only whitespace.
  grep -q '[^[:space:]]' "$file" || return 0

  shell="$(shell_of "$file")"

  if [ "$shell" != "none" ]; then
    lint_shell "$file" "$shell" "$label"
    return 0
  fi

  case "${template%.tmpl}" in
    *.json)
      jq empty "$file" || fail "$label: invalid JSON"
      ;;
    *.toml)
      python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' \
        "$file" || fail "$label: invalid TOML"
      ;;
    *.yaml | *.yml)
      if python_has yaml; then
        python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' \
          "$file" || fail "$label: invalid YAML"
      fi
      ;;
    *.plist)
      python3 -c 'import sys, plistlib; plistlib.load(open(sys.argv[1], "rb"))' \
        "$file" || fail "$label: invalid plist"
      ;;
    *.lua)
      if have nvim; then
        nvim --headless --clean -l /dev/stdin "$file" <<'EOF' || fail "$label: invalid Lua"
local ok, err = loadfile(_G.arg[1])
if not ok then
  io.stderr:write(err .. "\n")
  os.exit(1)
end
EOF
      fi
      ;;
    *zsh*)
      lint_shell "$file" zsh "$label"
      ;;
  esac
}

list_templates() {
  find "$source_root" -type f -name '*.tmpl' \
    ! -name '.chezmoi.toml.tmpl' \
    ! -name '*.age' \
    | sort
}

check_configuration() {
  name="$1"
  profiles="$2"
  ssh_agent="$3"
  extra_env="$4"

  printf '\n==> %s (%s, ssh agent: %s)\n' "$name" "$profiles" "$ssh_agent"

  config="$(init_config "$name" "$profiles" "$ssh_agent" "$extra_env")"
  out_dir="$test_root/$name"
  before=$failures
  count=0

  for template in $(list_templates); do
    relative="${template#"$source_root"/}"
    output="$out_dir/$relative"

    render "$config" "$template" "$output" || continue
    lint_rendered "$output" "$template" "$name: $relative"
    count=$((count + 1))
  done

  if ! DOTFILES_CI=true chezmoi --config "$config" --source "$repo_root" \
    --destination "$test_root/$name-home" \
    apply --dry-run --exclude scripts,encrypted >"$test_root/$name.apply.log" 2>&1; then
    cat "$test_root/$name.apply.log" >&2
    fail "$name: chezmoi apply --dry-run failed"
  fi

  check_ssh_agent_socket "$name" "$out_dir" "$ssh_agent"
  check_ci_excludes_encrypted "$name" "$config"

  if [ "$failures" -eq "$before" ]; then
    pass "$name: rendered and linted $count templates"
  fi
}

# The shell's SSH_AUTH_SOCK must point at the socket the agent creates.
check_ssh_agent_socket() {
  name="$1"
  out_dir="$2"
  ssh_agent="$3"

  [ "$ssh_agent" = "proton-pass" ] || return 0

  exported="$(sed -n 's/^export SSH_AUTH_SOCK="\(.*\)"$/\1/p' \
    "$out_dir/dot_zshenv.tmpl")"
  started="$(sed -n 's/.*--socket-path "\(.*\)".*/\1/p' \
    "$out_dir/dot_local/bin/executable_proton-pass-ssh-agent.tmpl")"

  if [ -z "$exported" ] || [ -z "$started" ]; then
    fail "$name: could not find Proton Pass socket paths"
  elif [ "$exported" != "$started" ]; then
    fail "$name: SSH_AUTH_SOCK ($exported) differs from agent socket ($started)"
  fi
}

# CI has no age identity, so nothing encrypted may remain managed.
check_ci_excludes_encrypted() {
  name="$1"
  config="$2"
  destination="$test_root/$name-home"

  managed="$(DOTFILES_CI=true chezmoi --config "$config" --source "$repo_root" \
    --destination "$destination" managed --include encrypted)"

  if [ -n "$managed" ]; then
    printf '%s\n' "$managed" >&2
    fail "$name: encrypted files are still managed with DOTFILES_CI=true"
  fi
}

# Static checks on template sources that do not depend on a configuration.
check_checksums() {
  printf '\n==> Checksum literals\n'
  before=$failures

  # Lines look like: sha512="<hex>" or sha256=<hex>
  matches="$(grep -rnoE --include='*.tmpl' --include='*.sh' \
    'sha(256|512)="?[0-9A-Fa-f][^"[:space:]]*' "$source_root" "$repo_root/scripts" || true)"

  printf '%s\n' "$matches" | awk 'NF' | while IFS= read -r match; do
    location="${match%%:sha*}"
    literal="${match#"$location":}"
    kind="${literal%%=*}"
    value="${literal#*=}"
    value="${value#\"}"

    case "$value" in
      '' | *'$'* | *'{{'*) continue ;;
    esac

    case "$kind" in
      sha256) expected=64 ;;
      sha512) expected=128 ;;
    esac

    if ! printf '%s' "$value" | grep -Eq "^[0-9a-f]{$expected}\$"; then
      printf 'FAIL: %s: %s is not %s lowercase hex digits\n' \
        "$location" "$kind" "$expected" >&2
      exit 1
    fi
  done || failures=$((failures + 1))

  [ "$failures" -ne "$before" ] || pass "checksum literals are well-formed"
}

# .osid renders as "darwin" or "linux-<os-release id>".
check_osid_comparisons() {
  printf '\n==> osid comparisons\n'

  bad="$(grep -rnoE '\.osid[^}]*' "$source_root" \
    | grep -oE '"[^"]*"' \
    | grep -vE '^"(darwin|linux-[a-z0-9._-]+)"$' || true)"

  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" >&2
    fail "osid is compared with values it can never have"
  else
    pass "osid comparisons use rendered values"
  fi
}

command -v chezmoi >/dev/null 2>&1 || die "missing command: chezmoi"
command -v jq >/dev/null 2>&1 || die "missing command: jq"
command -v python3 >/dev/null 2>&1 || die "missing command: python3"

have shellcheck || skip "shellcheck not installed; shell lint limited to syntax"
python_has yaml || skip "PyYAML not installed; YAML templates not parsed"
have nvim || skip "nvim not installed; Lua templates not parsed"

check_checksums
check_osid_comparisons

configurations="$CONFIGURATIONS"

if [ "$(uname -s)" = "Darwin" ]; then
  configurations="$configurations$DARWIN_CONFIGURATIONS"
fi

while IFS='|' read -r name profiles ssh_agent extra_env; do
  [ -n "$name" ] || continue
  check_configuration "$name" "$profiles" "$ssh_agent" "$extra_env"
done <<EOF
$configurations
EOF

if [ "$failures" -ne 0 ]; then
  die "$failures template check(s) failed"
fi

printf '\nAll template checks passed\n'
