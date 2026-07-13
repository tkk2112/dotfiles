#!/bin/sh
set -eu

REQUIRED_COMMANDS="
chezmoi
"

REQUIRED_FILES="
$HOME/.zshrc
$HOME/.zshenv
$HOME/.gitconfig
$HOME/.direnvrc
$HOME/.config/ghostty/config
$HOME/.config/tmux/tmux.conf
$HOME/.config/nvim/init.lua
"

REQUIRED_DIRS="
$HOME/.zsh
$HOME/.config/nvim/lua
"

SH_SYNTAX_FILES="
$HOME/.zshenv
$HOME/.direnvrc
"

ZSH_SYNTAX_FILES="
$HOME/.zshrc
"

TMUX_CONFIG_FILES="
$HOME/.config/tmux/tmux.conf
"

NVIM_LUA_FILES="
$HOME/.config/nvim/init.lua
"

USE_COLOR=false

if [ "${NO_COLOR:-}" ]; then
    USE_COLOR=false
elif [ "${FORCE_COLOR:-}" ]; then
    USE_COLOR=true
elif [ -t 1 ]; then
    USE_COLOR=true
elif [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    USE_COLOR=true
fi

if [ "$USE_COLOR" = "true" ]; then
    RESET="$(printf '\033[0m')"
    BOLD="$(printf '\033[1m')"
    DIM="$(printf '\033[2m')"
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    BLUE="$(printf '\033[34m')"
    CYAN="$(printf '\033[36m')"
else
    RESET=""
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
fi

log() {
    printf '%s\n' "$*"
}

section() {
    printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$*" "$RESET"
}

pass() {
    printf '%sPASS%s: %s\n' "$GREEN" "$RESET" "$*"
}

skip() {
    printf '%sSKIP%s: %s\n' "$YELLOW" "$RESET" "$*"
}

fail() {
    printf '%sFAIL%s: %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

run() {
    printf '%s+ %s%s\n' "$DIM" "$*" "$RESET"
    "$@"
}

check_commands() {
    section "Checking required commands"

    for cmd in $REQUIRED_COMMANDS; do
        log "Checking command: $cmd"
        if command -v "$cmd" >/dev/null 2>&1; then
            path="$(command -v "$cmd")"
            pass "command found: $cmd -> $path"
        else
            fail "missing command: $cmd"
        fi
    done
}

check_files() {
    section "Checking required files"

    for file in $REQUIRED_FILES; do
        log "Checking file: $file"
        if [ -f "$file" ]; then
            ls -l "$file"
            pass "file exists: $file"
        else
            fail "missing file: $file"
        fi
    done
}

check_dirs() {
    section "Checking required directories"

    for dir in $REQUIRED_DIRS; do
        log "Checking directory: $dir"
        if [ -d "$dir" ]; then
            ls -ld "$dir"
            pass "directory exists: $dir"
        else
            fail "missing directory: $dir"
        fi
    done
}

check_sh_syntax() {
    section "Checking POSIX shell syntax"

    for file in $SH_SYNTAX_FILES; do
        log "Checking sh syntax: $file"
        run sh -n "$file" || fail "shell syntax failed: $file"
        pass "sh syntax ok: $file"
    done
}

check_zsh_syntax() {
    section "Checking zsh syntax"

    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh syntax checks; zsh not installed"
        return 0
    fi

    run zsh --version

    for file in $ZSH_SYNTAX_FILES; do
        log "Checking zsh syntax: $file"
        run zsh -n "$file" || fail "zsh syntax failed: $file"
        pass "zsh syntax ok: $file"
    done
}

check_tmux_config() {
    section "Checking tmux config"

    if ! command -v tmux >/dev/null 2>&1; then
        skip "tmux config checks; tmux not installed"
        return 0
    fi

    run tmux -V

    tmux_test_socket="dotfiles-test-$$"
    tmux_test_session="config-test"

    cleanup_tmux_test_server() {
        env TMUX= tmux \
            -L "$tmux_test_socket" \
            kill-server \
            >/dev/null 2>&1 || :
    }
    trap 'cleanup_tmux_test_server' 0 1 2 15

    for file in $TMUX_CONFIG_FILES; do
        log "Checking tmux config: $file"

        cleanup_tmux_test_server

        # Start an isolated server with no configuration loaded.
        run env TMUX= tmux \
            -L "$tmux_test_socket" \
            -f /dev/null \
            new-session \
            -d \
            -s "$tmux_test_session" \
            || fail "failed to start isolated tmux server: $file"

        # Source the configuration once and propagate any parsing error.
        run env TMUX= tmux \
            -L "$tmux_test_socket" \
            source-file "$file" \
            || fail "tmux config failed: $file"

        cleanup_tmux_test_server
        pass "tmux config ok: $file"
    done

    trap - 0 1 2 15
}

check_nvim_config() {
    section "Checking nvim config"

    if ! command -v nvim >/dev/null 2>&1; then
        fail "nvim is required but was not installed"
    fi

    run nvim --version

    if ! nvim \
        --headless \
        --clean \
        "+lua if vim.fn.has('nvim-0.12') ~= 1 then vim.cmd('cquit 1') end" \
        +qa \
        >/dev/null 2>&1
    then
        fail "Neovim 0.12 or newer is required"
    fi

    if ! command -v tree-sitter >/dev/null 2>&1; then
        fail "tree-sitter CLI is required but was not installed"
    fi

    run tree-sitter --version

    for file in $NVIM_LUA_FILES; do
        log "Checking nvim config: $file"

        output_file="$(mktemp)"

        set +e
        nvim \
            --headless \
            -u "$file" \
            "+lua vim.wait(1000)" \
            +qa \
            >"$output_file" 2>&1
        nvim_status=$?
        set -e

        cat "$output_file"

        if [ "$nvim_status" -ne 0 ]; then
            rm -f "$output_file"
            fail "nvim exited with status $nvim_status: $file"
        fi

        # lazy.nvim catches many plugin errors internally, which means Neovim
        # may still exit with status zero. Treat the emitted errors as failures.
        if grep -E \
            'Error detected while processing|Failed to source|Failed to run `config`|Failed to run `build`|loop or previous error loading module|stack traceback:|E[0-9][0-9][0-9]+:|\[nvim-treesitter/install/[^]]+\] error:|Error during "tree-sitter build"' \
            "$output_file" \
            >/dev/null
        then
            rm -f "$output_file"
            fail "nvim reported startup or plugin errors: $file"
        fi

        rm -f "$output_file"
        pass "nvim config ok: $file"
    done
}

check_development_tools() {
    section "Checking development tools"

    if ! command -v chezmoi >/dev/null 2>&1; then
        skip "development tool checks; chezmoi not installed"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        skip "development tool checks; jq not installed"
        return 0
    fi

    if ! chezmoi data | jq -e '.profiles | index("development") != null' >/dev/null; then
        skip "development tool checks; development profile not enabled"
        return 0
    fi

    log "Checking command: cmake-language-server"

    if ! command -v cmake-language-server >/dev/null 2>&1; then
        skip "cmake-language-server not installed"
        return 0
    fi

    path="$(command -v cmake-language-server)"
    pass "command found: cmake-language-server -> $path"

    run cmake-language-server --version \
        || fail "cmake-language-server --version failed"

    pass "cmake-language-server version check ok"
}

check_ssh_config() {
    section "Checking SSH config"

    if ! command -v ssh >/dev/null 2>&1; then
        skip "ssh config checks; ssh not installed"
        return 0
    fi

    if [ ! -f "$HOME/.ssh/config" ]; then
        skip "ssh config checks; ~/.ssh/config not managed"
        return 0
    fi

    run ssh -F "$HOME/.ssh/config" -G example.invalid >/dev/null \
        || fail "ssh config failed"

    pass "ssh config ok"
}

check_chezmoi_state() {
    section "Checking chezmoi state"

    run chezmoi --version
    run chezmoi source-path >/dev/null || fail "chezmoi source-path failed"

    source_path="$(chezmoi source-path)"
    pass "chezmoi source path: $source_path"
}

print_environment() {
    section "Environment"

    log "USER=${USER:-}"
    log "HOME=$HOME"
    log "SHELL=${SHELL:-}"
    log "PWD=$PWD"
    log "DOTFILES_CI=${DOTFILES_CI:-}"
    log "DOTFILES_LOCATION=${DOTFILES_LOCATION:-}"
    log "GITHUB_ACTIONS=${GITHUB_ACTIONS:-}"
    log "USE_COLOR=$USE_COLOR"
    log "PATH=$PATH"
    log "DOTFILES_PROFILES=${DOTFILES_PROFILES:-}"

    if [ -f /etc/os-release ]; then
        log ""
        log "/etc/os-release:"
        cat /etc/os-release
    fi

    if command -v chezmoi >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        log ""
        log "Chezmoi profile data:"
        chezmoi data | jq '{os, osid, hostname, machine, profiles, git}'
    fi

    log ""
    log "Home directory:"
    ls -la "$HOME"

    log ""
    log "Config directory:"
    if [ -d "$HOME/.config" ]; then
        find "$HOME/.config" -maxdepth 3 -print | sort
    else
        log "$HOME/.config does not exist"
    fi
}

main() {
    log "${BOLD}${CYAN}Starting dotfiles install validation${RESET}"

    print_environment
    check_commands
    check_files
    check_dirs
    check_sh_syntax
    check_zsh_syntax
    check_tmux_config
    check_nvim_config
    check_development_tools
    check_ssh_config
    check_chezmoi_state

    section "Result"
    pass "Dotfiles install validation passed"
}

main "$@"
