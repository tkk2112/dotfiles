# Function to run gdb on a remote target
gdb_on_target() {
  if [[ -z "$1" ]]; then
    echo "Usage: gdb_on_target /path/to/executable [-- arg1 arg2 ...] [VAR1=value1 VAR2=value2 ...]"
    echo "       Use -- to separate program arguments from environment variables"
    return 1
  fi

  local file_path="$1"
  shift

  local args=()
  local env_vars=()
  local parsing_args=false

  # Parse arguments and environment variables
  for param in "$@"; do
    if [[ "$param" == "--" && "$parsing_args" == false ]]; then
      parsing_args=true
      continue
    fi

    if [[ "$parsing_args" == true ]]; then
      args+=("$param")
    elif [[ "$param" == *"="* ]]; then
      env_vars+=("$param")
    else
      args+=("$param")
    fi
  done

  local remote_host="rm"
  local remote_dir="."

  local filename
  filename="$(basename "$file_path")"

  local need_copy=true
  local local_md5=$(md5sum "$file_path" | awk '{print $1}')

  if ssh "$remote_host" "test -f ${remote_dir}/${filename}"; then
    local remote_md5=$(ssh "$remote_host" "md5sum ${remote_dir}/${filename}" | awk '{print $1}')

    if [[ "$local_md5" == "$remote_md5" ]]; then
      echo "File already exists on remote with matching checksum. Skipping copy."
      need_copy=false
    else
      echo "File exists on remote but has different checksum. Copying..."
    fi
  else
    echo "File doesn't exist on remote. Copying..."
  fi

  ssh "$remote_host" killall $filename 2>/dev/null || true

  if [[ "$need_copy" == true ]]; then
    scp "$file_path" "${remote_host}:${remote_dir}/" || {
      echo "Error: Failed to copy '$file_path' to '$remote_host'"
      return 1
    }
  fi

  local remote_command="gdbserver - ./${filename}"

  # Add program arguments if any
  if [[ ${#args[@]} -gt 0 ]]; then
    for arg in "${args[@]}"; do
      remote_command+=" \"$arg\""
    done
  fi

  if [[ ${#env_vars[@]} -gt 0 ]]; then
    local env_command="env"
    for var in "${env_vars[@]}"; do
      env_command+=" $var"
    done
    remote_command="${env_command} ${remote_command}"
  fi

  gdb -q "$file_path" \
    -ex "target remote | ssh -T $remote_host \"$remote_command\"" \
    -ex "break main" \
    -ex "continue"
}
