#!/bin/sh
set -eu

minimum_version="0.11"
bin_dir="${HOME}/.local/bin"
install_dir="${HOME}/.local/opt/neovim"

if command -v nvim >/dev/null 2>&1 &&
    nvim --headless --clean -u NONE -i NONE \
        -c 'if !has("nvim-0.11") | cquit | endif' \
        -c 'quit' >/dev/null 2>&1
then
    printf 'Neovim already satisfies the minimum version: '
    nvim --version | sed -n '1p'
    exit 0
fi

case "$(uname -m)" in
    x86_64 | amd64)
        arch="x86_64"
        ;;
    aarch64 | arm64)
        arch="arm64"
        ;;
    *)
        printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
esac

command -v curl >/dev/null 2>&1 || {
    printf 'curl is required to install Neovim\n' >&2
    exit 1
}

archive="nvim-linux-${arch}.tar.gz"
url="https://github.com/neovim/neovim/releases/latest/download/${archive}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

printf 'Installing Neovim >= %s for %s\n' "$minimum_version" "$arch"

curl -L \
    --proto '=https' \
    --tlsv1.2 \
    -sSf \
    "$url" \
    -o "$tmp_dir/$archive"

rm -rf "$install_dir"
mkdir -p "$install_dir" "$bin_dir"

tar -xzf "$tmp_dir/$archive" \
    --strip-components=1 \
    -C "$install_dir"

ln -sf "$install_dir/bin/nvim" "$bin_dir/nvim"

"$bin_dir/nvim" --version | sed -n '1p'
