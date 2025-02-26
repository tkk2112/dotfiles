#!/bin/bash

if [ ! -f "${HOME}/.proton_sync" ]; then
  exit 0
fi

# The rclone command itself handles SIGINT gracefully when using --resilient
# We just need to ensure we pass the signal through
trap graceful_shutdown SIGINT
graceful_shutdown() {
  echo "Graceful shutdown initiated..."
  kill -SIGINT $! 2> /dev/null
  wait $!
  echo "Shutdown complete"
  exit 0
}

available_folders=$("${HOME}"/.local/share/go/bin/rclone lsf --dirs-only protondrive: | sed 's#/$##' | sort)

while IFS= read -r folder; do
  [[ -z ${folder} || ${folder} =~ ^# ]] && continue

  # Check if folder exists in ProtonDrive
  if ! echo "$available_folders" | grep -q "^${folder}$"; then
    echo "Error: Folder '${folder}' not found in ProtonDrive"
    echo "Available folders:"
    echo "$available_folders"
    exit 1
  fi

  [ ! -d "${HOME}/ProtonDrive/${folder}" ] && mkdir -p "${HOME}/ProtonDrive/${folder}"

  echo "********** Syncing folder '${folder}' **********"

  "${HOME}"/.local/share/go/bin/rclone bisync \
    "protondrive:${folder}" "${HOME}/ProtonDrive/${folder}" \
    --compare size,modtime,checksum \
    --create-empty-src-dirs \
    --fix-case \
    --metadata \
    --protondrive-enable-caching=true \
    --protondrive-replace-existing-draft=true \
    --recover \
    --resilient \
    --resync \
    --resync-mode newer \
    --retries-sleep 1s \
    --slow-hash-sync-only \
    --verbose \
    "$@"

done < "${HOME}/.proton_sync"
