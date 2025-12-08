#!/bin/sh
# shellcheck shell=dash

options_spec() {
    cat <<'EOF'
--help|show this help message and exit.
-y, --assumeyes|automatically answer yes to all prompts.
--noupdate|do not check for updates before running.

--list-tasks|List all tasks in the playbook without executing anything.
--list-hosts|List all hosts that the playbook will target.
--list-tags|List all available tags in the playbook.
--tags|Run only tasks with specified tags (e.g. --tags ssh,git).
-v|Enable verbose mode (repeat for more verbosity).
EOF
}

show_help() {
    local script_name="${1:-$(basename "$0")}"
    cat <<EOF
Usage: ${script_name} [OPTIONS]

OPTIONS:
EOF

    options_spec | while IFS='|' read -r opt desc; do
        printf '  %-20s %s\n' "$opt" "$desc"
    done
}

# shellcheck disable=SC1091  # cannot follow sourced file
. scripts/library.sh
PROCESSED_ARGS=""

process_arguments() {
    local _assumeyes=${1}
    shift
    local _notupdate=${1}
    shift
    local _args=""

    while [ $# -gt 0 ]; do
        case "$1" in
        --help)
            show_help
            PROCESSED_ARGS=""
            return 1
            ;;
        -y | --assumeyes)
            shift
            set_flag "$_assumeyes"
            ;;
        --noupdate)
            shift
            set_flag "$_notupdate"
            ;;
        --)
            shift
            [ $# -gt 0 ] && _args="${_args:+$_args }$*"
            break
            ;;
        *)
            _args="${_args:+$_args }$1"
            shift
            ;;
        esac
    done
    export PROCESSED_ARGS="$_args"
    return 0
}

case "$0" in
*/options.sh | options.sh)
    err "this file is a library and must be sourced"
    ;;
esac
