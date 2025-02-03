# Function to run gdb on a remote target
gdb_on_target() {
  if [[ -z "$1" ]]; then
    echo "Usage: gdb_on_target /path/to/executable [VAR1=value1 VAR2=value2 ...]"
    return 1
  fi

  local file_path="$1"
  shift
  local env_vars=("$@")

  local remote_host="rm"
  local remote_dir="."

  local filename
  filename="$(basename "$file_path")"

  scp "$file_path" "${remote_host}:${remote_dir}/" || {
    echo "Error: Failed to copy '$file_path' to '$remote_host'"
    return 1
  }

  local remote_command="gdbserver - ./${filename}"
  if [[ ${#env_vars[@]} -gt 0 ]]; then
    remote_command="env"
    for var in "${env_vars[@]}"; do
      remote_command+=" $var"
    done
    remote_command+=" gdbserver - ./${filename}"
  fi

  gdb -q "$file_path" \
      -ex "target remote | ssh -T $remote_host \"$remote_command\"" \
      -ex "break main" \
      -ex "continue"
}
