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

INVALID_PROFILE_SETS="
development
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

test_profile_set() {
  profiles="$1"
  slug="$(profile_slug "$profiles")"
  config_file="$test_root/$slug.toml"
  destination="$test_root/$slug-home"

  printf '\n==> Testing profiles: %s\n' "$profiles"

  DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    run chezmoi init --config "$config_file" --source "$repo_root" --promptDefaults

  data_file="$test_root/$slug-data.json"
  chezmoi --config "$config_file" data >"$data_file"

  actual_profiles="$(jq -r '.profiles | join(",")' "$data_file")"

  if jq -e 'has("hasRoot") or has("base")' "$data_file" >/dev/null; then
    fail "legacy profile flags are still present for: $profiles"
  fi

  if [ "$actual_profiles" != "$profiles" ]; then
    fail "profile mismatch: expected '$profiles', got '$actual_profiles'"
  fi

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
}

test_invalid_profile_set() {
  profiles="$1"
  slug="invalid-$(profile_slug "$profiles")"
  config_file="$test_root/$slug.toml"
  output="$test_root/$slug.log"

  printf '\n==> Rejecting invalid profiles: %s\n' "$profiles"

  if DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    chezmoi init --config "$config_file" --source "$repo_root" --promptDefaults \
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

printf '%s\n' "$INVALID_PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
  test_invalid_profile_set "$profiles"
done
