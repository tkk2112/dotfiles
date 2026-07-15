if debian; then
  alias bat='batcat --theme=Coldark-Dark'
else
  alias bat='bat --theme=Coldark-Dark'
fi

alias less='bat'
alias more='bat'

alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias grep='grep --color=auto'

alias l='ls -1'
alias la='ls -A'
alias ll='ls -lah --git'
alias ls='lsd'

alias cz='chezmoi'
alias hookoff='git config --global core.hooksPath /dev/null'
alias hookon='git config --global --unset core.hooksPath'
alias tlf='tldr --list | fzf --preview "tldr {1} --color=always" --preview-window=right,70% | xargs tldr'
alias tmux='tmux -2'

alias dpigs='dpigs -H'
alias nonascii='ag "[^\x00-\x7F]"'
alias rot13='tr a-zA-Z n-za-mN-ZA-M'

alias vi='nvim'
alias vim='nvim'
