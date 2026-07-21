_gdb_on_target_usage() {
  print -u2 -- \
    "Usage: gdb-on-target EXECUTABLE [NAME=value ...] [-- PROGRAM_ARG ...]"
}

function gdb-on-target {
  emulate -L zsh
  setopt localoptions errreturn pipefail extendedglob

  if (($# == 0)); then
    _gdb_on_target_usage
    return 2
  fi

  local file_path=${1:A}
  shift

  if [[ ! -f $file_path ]]; then
    print -u2 -- "Executable does not exist: $file_path"
    return 1
  fi

  if [[ ! -x $file_path ]]; then
    print -u2 -- "File is not executable: $file_path"
    return 1
  fi

  local -a env_vars=()
  local -a program_args=()

  while (($# > 0)); do
    if [[ $1 == -- ]]; then
      shift
      program_args=("$@")
      break
    fi

    if [[ $1 != [A-Za-z_][A-Za-z0-9_]#=* ]]; then
      print -u2 -- "Expected an environment assignment or --: $1"
      _gdb_on_target_usage
      return 2
    fi

    env_vars+=("$1")
    shift
  done

  local command_name

  for command_name in cksum gdb scp ssh; do
    if ((!$+commands[$command_name])); then
      print -u2 -- "Missing command: $command_name"
      return 127
    fi
  done

  local remote_host=${GDB_ON_TARGET_HOST:-rm}
  local remote_dir=${GDB_ON_TARGET_DIR:-.}

  local filename=${file_path:t}
  local remote_path="${remote_dir%/}/$filename"
  local quoted_remote_path=${(q)remote_path}

  local target_config="$HOME/.config/gdb-on-target/targets/$filename.gdb"
  local -a gdb_extra_args=()

  if [[ -f $target_config ]]; then
    print -r -- "Using target-specific config: $target_config"
    gdb_extra_args=(-x "$target_config")
  fi

  if ! command ssh "$remote_host" \
    'command -v gdbserver >/dev/null 2>&1'; then
    print -u2 -- \
      "Could not connect to '$remote_host' or gdbserver is unavailable"
    return 1
  fi

  local local_checksum

  local_checksum=$(
    command cksum "$file_path" \
      | command awk '{ print $1 ":" $2 }'
  )

  if [[ -z $local_checksum ]]; then
    print -u2 -- "Could not calculate checksum: $file_path"
    return 1
  fi

  local remote_checksum=""
  local -i need_copy=1

  if command ssh "$remote_host" "test -f $quoted_remote_path"; then
    remote_checksum=$(
      command ssh "$remote_host" "cksum $quoted_remote_path" \
        2>/dev/null \
        | command awk '{ print $1 ":" $2 }'
    ) || remote_checksum=""

    if [[ -n $remote_checksum && $local_checksum == $remote_checksum ]]; then
      print -r -- \
        "Remote executable matches local checksum; skipping copy"

      need_copy=0
    else
      print -r -- \
        "Remote executable differs from local executable; copying"
    fi
  else
    print -r -- "Remote executable does not exist; copying"
  fi

  # Stop an older copy before replacing or launching the executable.
  if ! command ssh "$remote_host" \
    "killall ${(q)filename} >/dev/null 2>&1 || true"; then
    print -u2 -- "Could not connect to target: $remote_host"
    return 1
  fi

  if ((need_copy)); then
    local remote_destination="${remote_host}:${remote_dir%/}/"

    if ! command scp "$file_path" "$remote_destination"; then
      print -u2 -- \
        "Could not copy '$file_path' to '$remote_destination'"

      return 1
    fi
  fi

  local -a remote_argv=(env)

  if ((${#env_vars} > 0)); then
    remote_argv+=("${env_vars[@]}")
  fi

  remote_argv+=(
    gdbserver
    -
    "./$filename"
  )

  if ((${#program_args} > 0)); then
    remote_argv+=("${program_args[@]}")
  fi

  # Quote every argument before converting the array into the remote shell
  # command. This preserves spaces, quotes, globs, and shell metacharacters.
  local -a quoted_remote_argv
  quoted_remote_argv=("${(@q)remote_argv}")

  local remote_command
  remote_command="cd ${(q)remote_dir} && exec ${(j: :)quoted_remote_argv}"

  local -a ssh_argv=(
    ssh
    -T
    "$remote_host"
    "$remote_command"
  )

  local -a quoted_ssh_argv
  quoted_ssh_argv=("${(@q)ssh_argv}")

  local gdb_pipe_command="${(j: :)quoted_ssh_argv}"

  local -a gdb_command=(gdb)

  if [[ -n ${TMUX:-} ]] && command -v gdb-tmux >/dev/null 2>&1; then
    gdb_command=(gdb-tmux)
  fi

  command "${gdb_command[@]}" \
    -q \
    "$file_path" \
    "${gdb_extra_args[@]}" \
    -ex "set sysroot target:" \
    -ex "set exec-file-mismatch off" \
    -ex "target remote | $gdb_pipe_command"
}
