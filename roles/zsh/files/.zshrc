source ~/.zsh/functions/darwin.zsh

# Disable update prompt (Oh-My-Zsh setting)
export DISABLE_UPDATE_PROMPT=true
ZSH_CUSTOM_AUTOUPDATE_QUIET=true
ZSH_CUSTOM_AUTOUPDATE_NUM_WORKERS=8
ZSH_THEME="powerlevel10k/powerlevel10k"

zstyle :omz:plugins:ssh-agent agent-forwarding yes
zstyle :omz:plugins:ssh-agent quiet yes:
zstyle :omz:plugins:ssh-agent lazy yes

# Enable Powerlevel10k instant prompt (should be near the top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Ensure paths are unique
typeset -U path cdpath fpath manpath

# Platform-specific configurations
if darwin; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi

# Oh-My-Zsh configuration
plugins=(
  aliases
  command-not-found
  colored-man-pages
  branch
  direnv
  fzf
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  nmap
  rsync
  ssh-agent
  sudo
  uv
  virtualenv
  autoupdate
)
if darwin; then
  plugins+=(macos brew)
fi

source $ZSH/oh-my-zsh.sh

# Load options
source ~/.zsh/options.zsh

# Load history settings after Oh-My-Zsh
source ~/.zsh/history.zsh

# Load keybindings
source ~/.zsh/keybindings.zsh

# Load aliases
source ~/.zsh/aliases.zsh

# Load directory hashes/options
source ~/.zsh/dirs.zsh

# Load functions
for func_file in ~/.zsh/functions/*.zsh; do
  source "$func_file"
done

# Platform-specific configurations
if darwin; then
  # iTerm2 shell integration
  [ -e "${HOME}/.iterm2_shell_integration.zsh" ] && source "${HOME}/.iterm2_shell_integration.zsh"

  # Google Cloud SDK
  source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
  source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"
else
  source ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme
fi

# Load Powerlevel10k configuration
[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Load local overrides if available
[[ -r ~/.zshrc_local ]] && source ~/.zshrc_local

# Add Rust's cargo binary directory to PATH
[ -r "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# Add Python's argcomplete bash completion directory to zsh completion paths (fpath)
# This enables tab completion for Python scripts using argcomplete
if [ -d /usr/lib/python3/dist-packages/argcomplete/bash_completion.d ]; then
  fpath=( /usr/lib/python3/dist-packages/argcomplete/bash_completion.d "${fpath[@]}" )
fi

# Source additional environment variables or scripts
[ -f "$HOME/.local/share/../bin/env" ] && source "$HOME/.local/share/../bin/env"

# Load additional work functions from ProtonDrive
if [[ -d ~/ProtonDrive/work/zsh ]]; then
  for func_file in ~/ProtonDrive/work/zsh/*.zsh; do
    if [[ -f "$func_file" ]]; then
      source "$func_file"
    fi
  done
fi
