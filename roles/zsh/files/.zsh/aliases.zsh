source ~/.zsh/functions/indentify.zsh
# Platform-specific alias for 'bat'
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

alias l='ls -CF'
alias la='ls -A'
alias ll='ls -lah'
alias ls='ls --color'

alias dpigs='dpigs -H'
alias rot13='tr a-zA-Z n-za-mN-ZA-M'
alias tmux='tmux -2'

alias hookoff='git config --global core.hooksPath /dev/null'
alias hookon='git config --global --unset core.hooksPath'

alias nonascii='ag "[^\x00-\x7F]"'
