#!/bin/sh
set -eu

REPRESENTATIVE_PROFILE_SETS="
workstation
headless
workstation,development
workstation,laptop
workstation,gaming
headless,server
workstation,owned
workstation,laptop,development,gaming,server,owned
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

generate_all_profile_sets() {
  for role in workstation headless; do
    for development in "" development; do
      for gaming in "" gaming; do
        for server in "" server; do
          for laptop in "" laptop; do
            for owned in "" owned; do
              profiles="$role"

              for capability in \
                "$development" \
                "$gaming" \
                "$server" \
                "$laptop" \
                "$owned"; do
                if [ -n "$capability" ]; then
                  profiles="$profiles,$capability"
                fi
              done

              printf '%s\n' "$profiles"
            done
          done
        done
      done
    done
  done
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
  data_file="$test_root/$slug-data.json"

  printf '\n==> Testing profiles: %s\n' "$profiles"

  DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
    run chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults

  chezmoi --config "$config_file" data >"$data_file"

  actual_profiles="$(jq -r '.profiles | join(",")' "$data_file")"

  if jq -e 'has("hasRoot") or has("base")' "$data_file" >/dev/null; then
    fail "legacy profile flags are still present for: $profiles"
  fi

  if [ "$actual_profiles" != "$profiles" ]; then
    fail "profile mismatch: expected '$profiles', got '$actual_profiles'"
  fi

  run chezmoi \
    --config "$config_file" \
    --source "$repo_root" \
    --destination "$destination" \
    apply \
    --dry-run \
    --exclude scripts,encrypted

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
    chezmoi init \
    --config "$config_file" \
    --source "$repo_root" \
    --promptDefaults \
    >"$output" 2>&1; then
    cat "$output"
    fail "invalid profile set was accepted: $profiles"
  fi
}

command -v chezmoi >/dev/null 2>&1 \
  || fail "missing command: chezmoi"
command -v jq >/dev/null 2>&1 \
  || fail "missing command: jq"

profile_scope="${DOTFILES_PROFILE_SCOPE:-representative}"

case "$profile_scope" in
  representative | all) ;;
  *) fail "unknown DOTFILES_PROFILE_SCOPE: $profile_scope" ;;
esac

if [ -n "${DOTFILES_PROFILE_SET:-}" ]; then
  if [ "$profile_scope" = "all" ]; then
    fail "DOTFILES_PROFILE_SET cannot be combined with DOTFILES_PROFILE_SCOPE=all"
  fi

  test_profile_set "$DOTFILES_PROFILE_SET"
  exit 0
fi

case "$profile_scope" in
  representative)
    valid_profile_sets="$REPRESENTATIVE_PROFILE_SETS"
    ;;
  all)
    valid_profile_sets="$(generate_all_profile_sets)"
    ;;
esac

printf '%s\n' "$valid_profile_sets" \
  | awk 'NF' \
  | while IFS= read -r profiles; do
    test_profile_set "$profiles"
  done

printf '%s\n' "$INVALID_PROFILE_SETS" \
  | awk 'NF' \
  | while IFS= read -r profiles; do
    test_invalid_profile_set "$profiles"
  done
