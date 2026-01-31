# Function to manage tmux sessions
tm() {
    local session
    session=$(hostname -s)
    if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session" -n "main"
        tmux split-window -h -t "$session:main" -c ~/work -d
        tmux new-window -t "$session" -n "work" -c ~/work -d
        tmux split-window -h -t "$session:work" -c ~/work -d
        tmux new-window -t "$session" -n "misc" -c ~ -d
        tmux select-window -t "$session:work"
    fi
    tmux attach-session -t "$session"
}
