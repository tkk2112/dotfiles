export EDITOR="nvim"
export VISUAL="vim"

export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

export PATH="$HOME/bin:$PATH"

export MANROFFOPT="-c"

if [[ "$OSTYPE" == "darwin"* ]]; then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
else
  export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
fi

export ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
export ZSH="$HOME/.oh-my-zsh"
