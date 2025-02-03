# Function to run gdb in a tmux session with dashboard
gdb-tmux() {
  local window="$(tmux new-window -c $PWD -PF "#D")"
  local stack="$(tmux split-window -h -p 71 -PF "#D" "echo dashboard stack -output \$(tty) > ~/.gdbinit.d/tmux.stack;reset")"
  local register="$(tmux split-window -t 0 -v -p 47 -PF "#D" "echo dashboard register -output \$(tty) > ~/.gdbinit.d/tmux.register;reset")"
  local src="$(tmux split-window -t 2 -v -p 30 -PF "#D" "echo dashboard source -output \$(tty) > ~/.gdbinit.d/tmux.source;reset")"
  local assembly="$(tmux split-window -t 2 -h -p 37 -PF "#D" "echo dashboard assembly -output \$(tty) > ~/.gdbinit.d/tmux.assembly;reset")"
  local variable="$(tmux split-window -t 2 -v -p 40 -PF "#D" "echo dashboard variable -output \$(tty) > ~/.gdbinit.d/tmux.variable;reset")"

  gdb "$@"
  tmux kill-window -t "$window"
  rm ~/.gdbinit.d/tmux.*
}

