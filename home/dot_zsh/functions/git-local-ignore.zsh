git-local-ignore() {
    local git_dir pattern

    git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || {
        echo "Error: Not inside a Git repository" >&2
        return 1
    }

    if (( $# == 0 )); then
        echo "Usage: git-local-ignore <pattern> [...]" >&2
        return 1
    fi

    for pattern in "$@"; do
        if ! grep -Fxq -- "$pattern" "$git_dir/info/exclude" 2>/dev/null; then
            print -r -- "$pattern" >> "$git_dir/info/exclude"
            echo "Ignored locally: $pattern"
        fi
    done
}

