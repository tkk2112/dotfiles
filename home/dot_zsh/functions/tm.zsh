tm() {
  local session
  session="$(hostname -s)"

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -n main
    tmux split-window -h -t "$session:main" -c ~/code -d
    tmux new-window -t "$session" -n code -c ~/code -d
    tmux split-window -h -t "$session:code" -c ~/code -d
    tmux new-window -t "$session" -n misc -c ~ -d
    tmux select-window -t "$session:code"
  fi

  tmux attach-session -t "$session"
}
