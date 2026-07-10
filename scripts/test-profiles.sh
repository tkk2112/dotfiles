#!/bin/sh
set -eu

PROFILE_SETS="
base
base,development
base,workstation,development
base,workstation,development,owned
base,headless,server,owned
base,workstation,development,gaming,server,owned
"

repo_root="${DOTFILES_LOCATION:-$(git rev-parse --show-toplevel)}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run() {
    printf '+ %s\n' "$*"
    "$@"
}

test_profile_set() {
    profiles="$1"

    printf '\n==> Testing profiles: %s\n' "$profiles"

    config_file="/tmp/chezmoi-profile-test-$(printf '%s' "$profiles" | tr ',' '-').toml"
    destination="$(mktemp -d)"

    rm -f "$config_file"

    DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
        run chezmoi init --config "$config_file" --source "$repo_root" --promptDefaults

    actual_profiles="$(
        chezmoi --config "$config_file" data |
            jq -r '.profiles | join(",")'
    )"

    if [ "$actual_profiles" != "$profiles" ]; then
        fail "profile mismatch: expected '$profiles', got '$actual_profiles'"
    fi

    run chezmoi --config "$config_file" \
        --source "$repo_root" \
        --destination "$destination" \
        apply --dry-run --exclude scripts,encrypted

    for script in "$repo_root"/home/.chezmoiscripts/*.tmpl; do
        out="/tmp/$(basename "$script" .tmpl)-$(printf '%s' "$profiles" | tr ',' '-')"

        DOTFILES_CI=true DOTFILES_PROFILES="$profiles" \
            run chezmoi --config "$config_file" execute-template < "$script" > "$out"

        run sh -n "$out"
    done

    rm -f "$config_file"
    rm -rf "$destination"
}

command -v chezmoi >/dev/null 2>&1 || fail "missing command: chezmoi"
command -v jq >/dev/null 2>&1 || fail "missing command: jq"

printf '%s\n' "$PROFILE_SETS" | awk 'NF' | while IFS= read -r profiles; do
    test_profile_set "$profiles"
done
