# Proton Pass SSH key utilities for Zsh.
#
# Configuration:
#   export PROTON_PASS_SSH_VAULT=Keys
#
# Commands:
#   pp-ssh-generate    Generate and store a new key pair.
#   pp-ssh-import      Import an existing key pair.
#   pp-ssh-export      Export a stored key pair.
#   pp-ssh-update      Replace an existing stored key pair in place.
#   pp-ssh-rotate      Generate a replacement and update an item in place.
#   pp-ssh-check       Verify a stored private/public pair.
#   pp-ssh-status      Compare a local private key with a stored item.
#   pp-ssh-public      Print a stored public key.
#   pp-ssh-list        List SSH keys stored in the configured vault.
#   pp-ssh-fingerprint Print a stored key's fingerprint.
#   pp-ssh-help        Show command usage.

_pp_ssh_require() {
  emulate -L zsh

  local command_name

  for command_name in "$@"; do
    if ((!$+commands[$command_name])); then
      print -u2 -- "missing command: $command_name"
      return 127
    fi
  done
}

_pp_ssh_vault() {
  print -r -- "${PROTON_PASS_SSH_VAULT:-Keys}"
}

_pp_ssh_list_json() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local vault=${1:-$(_pp_ssh_vault)}

  command pass-cli item list \
    --output json \
    --filter-type ssh-key \
    --filter-state active \
    "$vault"
}

_pp_ssh_item_count() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local title=$1
  local vault=${2:-$(_pp_ssh_vault)}

  _pp_ssh_list_json "$vault" \
    | command jq -er \
      --arg title "$title" \
      '[.items[]? | select(.title == $title)] | length'
}

# Resolve one active SSH item by title and print:
#   SHARE_ID<TAB>ITEM_ID
#
# Trashed items are excluded by the list filters. Duplicate active titles are
# rejected instead of allowing pass-cli title lookup to select an arbitrary item.
_pp_ssh_resolve_item() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local title=$1
  local vault=${2:-$(_pp_ssh_vault)}
  local list_json count

  list_json=$(_pp_ssh_list_json "$vault")

  count=$(
    print -r -- "$list_json" \
      | command jq -er \
        --arg title "$title" \
        '[.items[]? | select(.title == $title)] | length'
  )

  case $count in
    0)
      print -u2 -- "active SSH key not found: $title"
      return 1
      ;;
    1)
      ;;
    *)
      print -u2 -- \
        "multiple active SSH keys have the title '$title' in vault '$vault'"
      return 1
      ;;
  esac

  print -r -- "$list_json" \
    | command jq -er \
      --arg title "$title" \
      '.items[]
       | select(.title == $title)
       | [.share_id, .id]
       | @tsv'
}

# Resolve the exact item returned by an item-create command. The item ID comes
# directly from pass-cli, so this does not perform another title lookup.
_pp_ssh_created_item_ref() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local item_id=$1
  local vault=${2:-$(_pp_ssh_vault)}

  command pass-cli item view \
    --vault-name "$vault" \
    --item-id "$item_id" \
    --output json \
    | command jq -er \
      --arg item_id "$item_id" \
      'select(.item.id == $item_id)
       | [.item.share_id, .item.id]
       | @tsv'
}

_pp_ssh_field() {
  emulate -L zsh

  local share_id=$1
  local item_id=$2
  local field=$3

  command pass-cli item view \
    --share-id "$share_id" \
    --item-id "$item_id" \
    --field "$field"
}

_pp_ssh_public_line() {
  command awk 'NF >= 2 { print; exit }'
}

_pp_ssh_public_identity() {
  command awk 'NF >= 2 { print $1, $2; exit }'
}

_pp_ssh_tmpdir() {
  emulate -L zsh

  local tmpdir

  umask 077
  tmpdir=$(command mktemp -d "${TMPDIR:-/tmp}/pp-ssh.XXXXXX") || return
  command chmod 700 "$tmpdir" || {
    command rm -rf -- "$tmpdir"
    return 1
  }

  print -r -- "$tmpdir"
}

_pp_ssh_normalize_private_file() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local source_file=$1
  local destination_file=$2

  # Some pass-cli versions reject otherwise valid OpenSSH private keys when blank
  # lines follow the END boundary. Work on a protected temporary copy and
  # remove only trailing blank/whitespace-only lines; never modify the source.
  command awk '
    {
      lines[NR] = $0
      if ($0 !~ /^[[:space:]]*$/)
        last = NR
    }
    END {
      if (!last)
        exit 1

      for (i = 1; i <= last; i++)
        print lines[i]
    }
  ' "$source_file" >|"$destination_file"

  command chmod 600 "$destination_file"
}

_pp_ssh_derive_public() {
  emulate -L zsh
  setopt localoptions pipefail

  local private_file=$1

  command ssh-keygen -y -f "$private_file" \
    | _pp_ssh_public_line
}

_pp_ssh_validate_public_files() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local first_file=$1
  local second_file=$2
  local first_identity second_identity

  first_identity=$(
    command awk 'NF >= 2 { print $1, $2; exit }' "$first_file"
  )

  second_identity=$(
    command awk 'NF >= 2 { print $1, $2; exit }' "$second_file"
  )

  if [[ -z $first_identity ||
    -z $second_identity ||
    $first_identity != $second_identity ]]; then
    print -u2 -- 'public keys do not match'
    return 1
  fi
}

_pp_ssh_validate_pair() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local private_file=$1
  local public_file=$2
  local derived stored

  derived=$(
    _pp_ssh_derive_public "$private_file" \
      | _pp_ssh_public_identity
  )

  stored=$(
    command awk 'NF >= 2 { print $1, $2; exit }' "$public_file"
  )

  if [[ -z $derived || -z $stored || $derived != $stored ]]; then
    print -u2 -- 'private and public keys do not match'
    return 1
  fi
}

_pp_ssh_private_is_protected() {
  emulate -L zsh

  local private_file=$1

  if command ssh-keygen \
    -y \
    -P '' \
    -f "$private_file" \
    >/dev/null 2>&1; then
    print -r -- false
  else
    print -r -- true
  fi
}

_pp_ssh_detect_key_type() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local public_file=$1
  local algorithm bits

  algorithm=$(
    command awk 'NF >= 2 { print $1; exit }' "$public_file"
  )

  case $algorithm in
    ssh-ed25519)
      print -r -- ed25519
      ;;
    ssh-rsa)
      bits=$(
        command ssh-keygen -lf "$public_file" \
          | command awk 'NR == 1 { print $1 }'
      )
      print -r -- "rsa${bits:-unknown}"
      ;;
    ecdsa-sha2-nistp256)
      print -r -- ecdsa256
      ;;
    ecdsa-sha2-nistp384)
      print -r -- ecdsa384
      ;;
    ecdsa-sha2-nistp521)
      print -r -- ecdsa521
      ;;
    sk-ssh-ed25519@openssh.com)
      print -r -- ed25519-sk
      ;;
    sk-ecdsa-sha2-nistp256@openssh.com)
      print -r -- ecdsa256-sk
      ;;
    '')
      print -r -- unknown
      ;;
    *)
      print -r -- "$algorithm"
      ;;
  esac
}

_pp_ssh_set_metadata() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn

  local share_id=$1
  local item_id=$2
  local source=$3
  local key_type=$4
  local protected=$5

  command pass-cli item update \
    --share-id "$share_id" \
    --item-id "$item_id" \
    --field 'pp_managed=true' \
    --field "pp_source=$source" \
    --field "pp_key_type=$key_type" \
    --field "pp_passphrase_protected=$protected"
}

_pp_ssh_update_item() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn

  local share_id=$1
  local item_id=$2
  local private_file=$3
  local public_file=$4
  local source=$5
  local key_type=$6
  local protected=$7
  local private_key public_key

  public_key=$(<"$public_file")
  private_key=$(<"$private_file")
  private_key+=$'\n'

  command pass-cli item update \
    --share-id "$share_id" \
    --item-id "$item_id" \
    --field "private_key=$private_key" \
    --field "public_key=$public_key" \
    --field 'pp_managed=true' \
    --field "pp_source=$source" \
    --field "pp_key_type=$key_type" \
    --field "pp_passphrase_protected=$protected"

  unset private_key
}

_pp_ssh_verify_stored_public() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local share_id=$1
  local item_id=$2
  local title=$3
  local public_file=$4
  local local_identity stored_identity

  local_identity=$(
    command awk 'NF >= 2 { print $1, $2; exit }' "$public_file"
  )

  stored_identity=$(
    _pp_ssh_field "$share_id" "$item_id" public_key \
      | _pp_ssh_public_identity
  )

  if [[ -z $local_identity ||
    -z $stored_identity ||
    $local_identity != $stored_identity ]]; then
    print -u2 -- "stored public key does not match: $title"
    return 1
  fi
}

_pp_ssh_check_item() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn pipefail

  local share_id=$1
  local item_id=$2
  local title=$3
  local tmpdir private_file public_file

  tmpdir=$(_pp_ssh_tmpdir)
  private_file=$tmpdir/private
  public_file=$tmpdir/public

  (
    trap '
      rc=$?
      command rm -rf -- "$tmpdir"
      exit "$rc"
    ' EXIT

    _pp_ssh_field "$share_id" "$item_id" private_key >|"$private_file"
    command chmod 600 "$private_file"

    _pp_ssh_field "$share_id" "$item_id" public_key \
      | _pp_ssh_public_line >|"$public_file"
    command chmod 644 "$public_file"

    _pp_ssh_validate_pair "$private_file" "$public_file"
    print -r -- "private and public keys match: $title"
  ) || return $?
}

_pp_ssh_write_pair() {
  emulate -L zsh
  setopt localoptions errreturn

  local force=$1
  local private_source=$2
  local public_source=$3
  local destination=${4:A}
  local directory=${destination:h}
  local private_tmp=
  local public_tmp=

  if [[ -e $destination && ! -f $destination ]]; then
    print -u2 -- "destination is not a regular file: $destination"
    return 1
  fi

  if [[ -e ${destination}.pub && ! -f ${destination}.pub ]]; then
    print -u2 -- "destination is not a regular file: ${destination}.pub"
    return 1
  fi

  if ((!force)) && [[ -e $destination || -e ${destination}.pub ]]; then
    print -u2 -- "destination already exists: $destination or ${destination}.pub"
    print -u2 -- 'rerun with --force to replace the existing pair'
    return 1
  fi

  command mkdir -p -- "$directory"

  if [[ $directory == ${HOME:A}/.ssh ]]; then
    command chmod 700 "$directory"
  fi

  (
    trap '
      rc=$?
      [[ -n $private_tmp ]] && command rm -f -- "$private_tmp"
      [[ -n $public_tmp ]] && command rm -f -- "$public_tmp"
      exit "$rc"
    ' EXIT

    umask 077
    private_tmp=$(command mktemp "${destination}.tmp.XXXXXX")
    public_tmp=$(command mktemp "${destination}.pub.tmp.XXXXXX")

    command cat -- "$private_source" >|"$private_tmp"
    command chmod 600 "$private_tmp"

    command cat -- "$public_source" >|"$public_tmp"
    command chmod 644 "$public_tmp"

    command mv -f -- "$private_tmp" "$destination"
    private_tmp=

    command mv -f -- "$public_tmp" "${destination}.pub"
    public_tmp=
  ) || return $?

  print -r -- "installed: $destination"
  print -r -- "installed: ${destination}.pub"
}

pp-ssh-help() {
  cat <<'EOF_HELP'
Proton Pass SSH key utilities

Configuration:
  PROTON_PASS_SSH_VAULT   Vault name. Default: Keys

Item selection:
  Titles are resolved only against active SSH items. Exactly one match is
  required, then all reads and updates use its share ID and item ID. Trashed
  items are ignored.

Commands:
  pp-ssh-generate [-p] [-t TYPE] [-C COMMENT] [-o DEST] TITLE
      Generate a new Proton Pass SSH item.
      TYPE is ed25519 (default), rsa2048, or rsa4096.
      -p enables passphrase protection.
      -o exports the new pair after creation.

  pp-ssh-import [--update] [-p] [-P PUBLIC_KEY] PRIVATE_KEY [TITLE]
      Import an existing private key as a new Proton Pass item.
      Refuses to create a duplicate title. Use --update to replace the key
      pair in the one active item while preserving its title, ID, and history.
      TITLE defaults to the private key filename.
      -P verifies against an explicit public-key file; without it, the public
      key is derived from PRIVATE_KEY. A sibling PRIVATE_KEY.pub is used when
      present. The private key is normalized through a mode-0600 temporary copy
      so strict pass-cli parsers accept files with trailing blank lines.
      Passphrase protection is detected automatically; -p forces it on.

  pp-ssh-export [-f|--force] TITLE [DEST]
      Export a stored pair. DEST defaults to ~/.ssh/TITLE.

  pp-ssh-update [-P PUBLIC_KEY] TITLE PRIVATE_KEY
      Replace the key pair in an existing item without changing its title or ID.
      Key type and passphrase protection are detected automatically.
      Proton Pass item history provides rollback.

  pp-ssh-rotate [-f] [-p] [-t TYPE] [-C COMMENT] [-o DEST] TITLE
      Generate a temporary replacement with ssh-keygen and update the existing
      Proton Pass item in place. TYPE is ed25519 (default), rsa2048,
      or rsa4096. -p prompts for a new passphrase.
      -o exports the rotated pair after the update.

  pp-ssh-check TITLE
      Verify that the stored private and public keys match.

  pp-ssh-status TITLE [PRIVATE_KEY]
      Compare a local private key with the stored item.
      PRIVATE_KEY defaults to ~/.ssh/TITLE.

  pp-ssh-list [-l]
      List SSH key item titles in the configured vault.
      -l includes managed metadata and modification time.

  pp-ssh-public TITLE
      Print the stored public key.

  pp-ssh-fingerprint TITLE
      Print the stored public key fingerprint.

Managed metadata fields:
  pp_managed
  pp_source
  pp_key_type
  pp_passphrase_protected
EOF_HELP
}

pp-ssh-list() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  local detailed=0
  local OPTIND=1 opt

  while getopts ':l' opt; do
    case $opt in
      l) detailed=1 ;;
      *)
        print -u2 -- 'usage: pp-ssh-list [-l]'
        return 2
        ;;
    esac
  done

  shift $((OPTIND - 1))

  if (($# != 0)); then
    print -u2 -- 'usage: pp-ssh-list [-l]'
    return 2
  fi

  _pp_ssh_require pass-cli jq

  local vault=$(_pp_ssh_vault)
  local list_json count

  list_json=$(_pp_ssh_list_json "$vault")

  count=$(
    print -r -- "$list_json" \
      | command jq -r '.items | length'
  )

  if ((count == 0)); then
    print -r -- "no SSH keys found in vault: $vault"
    return 0
  fi

  if ((!detailed)); then
    print -r -- "$list_json" \
      | command jq -r '.items | sort_by(.title)[] | .title'
    return
  fi

  local share_id item_id item_json details
  local title key_type protected source modified protected_label
  local table=$'TITLE\tTYPE\tPASSPHRASE\tSOURCE\tMODIFIED'

  while IFS=$'	' read -r share_id item_id; do
    [[ -n $share_id && -n $item_id ]] || continue

    # Fetch each exact item by ID. Besides avoiding duplicate-title
    # ambiguity, this gives us metadata and modify_time from one snapshot.
    item_json=$(
      command pass-cli item view \
        --share-id "$share_id" \
        --item-id "$item_id" \
        --output json
    )

    details=$(
      print -r -- "$item_json" \
        | command jq -r '
          def field($name):
            ([
              .item.content.extra_fields[]?
              | select(.name == $name)
              | (.content.Text // .content.Hidden // empty)
            ][0] // "unknown");

          [
            .item.content.title,
            field("pp_key_type"),
            field("pp_passphrase_protected"),
            field("pp_source"),
            .item.modify_time
          ]
          | @tsv
        '
    )

    IFS=$'\t' read -r \
      title key_type protected source modified <<<"$details"

    case $protected in
      true) protected_label=yes ;;
      false) protected_label=no ;;
      *) protected_label=unknown ;;
    esac

    table+=$'\n'"${title}"$'\t'"${key_type:-unknown}"$'\t'"$protected_label"$'\t'"${source:-unknown}"$'\t'"${modified:-unknown}"
  done < <(
    print -r -- "$list_json" \
      | command jq -r '.items | sort_by(.title)[] | [.share_id, .id] | @tsv'
  )

  if (($+commands[column])); then
    print -r -- "$table" \
      | command column -t -s $'\t'
  else
    print -r -- "$table"
  fi
}

pp-ssh-public() {
  emulate -L zsh
  setopt localoptions errreturn pipefail

  if (($# != 1)); then
    print -u2 -- 'usage: pp-ssh-public TITLE'
    return 2
  fi

  _pp_ssh_require pass-cli jq awk

  local title=$1
  local vault=$(_pp_ssh_vault)
  local ref share_id item_id

  ref=$(_pp_ssh_resolve_item "$title" "$vault")
  IFS=$'\t' read -r share_id item_id <<<"$ref"

  _pp_ssh_field "$share_id" "$item_id" public_key \
    | _pp_ssh_public_line
}

pp-ssh-fingerprint() {
  emulate -L zsh
  setopt localoptions errreturn

  if (($# != 1)); then
    print -u2 -- 'usage: pp-ssh-fingerprint TITLE'
    return 2
  fi

  _pp_ssh_require pass-cli jq ssh-keygen awk mktemp

  local title=$1
  local tmpdir public_file

  tmpdir=$(_pp_ssh_tmpdir)
  public_file=$tmpdir/public

  (
    trap '
      rc=$?
      command rm -rf -- "$tmpdir"
      exit "$rc"
    ' EXIT

    pp-ssh-public "$title" >|"$public_file"
    command ssh-keygen -lf "$public_file"
  ) || return $?
}

pp-ssh-check() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn pipefail

  if (($# != 1)); then
    print -u2 -- 'usage: pp-ssh-check TITLE'
    return 2
  fi

  _pp_ssh_require pass-cli jq ssh-keygen awk mktemp

  local title=$1
  local vault=$(_pp_ssh_vault)
  local ref share_id item_id

  ref=$(_pp_ssh_resolve_item "$title" "$vault")
  IFS=$'\t' read -r share_id item_id <<<"$ref"

  _pp_ssh_check_item "$share_id" "$item_id" "$title"
}

pp-ssh-generate() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn

  local use_password=0
  local key_type=ed25519
  local comment=
  local destination=
  local OPTIND=1 opt

  while getopts ':pt:C:o:' opt; do
    case $opt in
      p) use_password=1 ;;
      t) key_type=$OPTARG ;;
      C) comment=$OPTARG ;;
      o) destination=${OPTARG:A} ;;
      *)
        print -u2 -- \
          'usage: pp-ssh-generate [-p] [-t TYPE] [-C COMMENT] [-o DEST] TITLE'
        return 2
        ;;
    esac
  done

  shift $((OPTIND - 1))

  if (($# != 1)); then
    print -u2 -- \
      'usage: pp-ssh-generate [-p] [-t TYPE] [-C COMMENT] [-o DEST] TITLE'
    return 2
  fi

  case $key_type in
    ed25519 | rsa2048 | rsa4096) ;;
    *)
      print -u2 -- "unsupported key type: $key_type"
      return 2
      ;;
  esac

  _pp_ssh_require pass-cli ssh-keygen awk mktemp jq

  local title=$1
  local vault=$(_pp_ssh_vault)
  local protected=false
  local item_count item_id ref share_id
  local -a args

  item_count=$(_pp_ssh_item_count "$title" "$vault")

  if ((item_count > 0)); then
    print -u2 -- "SSH key already exists: $title"
    print -u2 -- 'use pp-ssh-rotate to replace it with a newly generated key'
    return 1
  fi

  [[ -n $comment ]] || comment=$title
  ((use_password)) && protected=true

  args=(
    item create ssh-key generate
    --vault-name "$vault"
    --title "$title"
    --key-type "$key_type"
    --comment "$comment"
  )

  ((use_password)) && args+=(--password)

  item_id=$(command pass-cli "${args[@]}")

  if [[ -z $item_id ]]; then
    print -u2 -- 'pass-cli did not return an item ID'
    return 1
  fi

  ref=$(_pp_ssh_created_item_ref "$item_id" "$vault")
  IFS=$'\t' read -r share_id item_id <<<"$ref"

  _pp_ssh_set_metadata \
    "$share_id" \
    "$item_id" \
    generated \
    "$key_type" \
    "$protected"

  _pp_ssh_check_item "$share_id" "$item_id" "$title"

  if [[ -n $destination ]]; then
    pp-ssh-export "$title" "$destination"
  fi
}

pp-ssh-import() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn pipefail

  local update=0
  local force_password=0
  local supplied_public=

  while (($#)); do
    case $1 in
      --update)
        update=1
        shift
        ;;
      -p)
        force_password=1
        shift
        ;;
      -P)
        if (($# < 2)); then
          print -u2 -- 'pp-ssh-import: -P requires a public-key path'
          return 2
        fi
        supplied_public=${2:A}
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        print -u2 -- \
          'usage: pp-ssh-import [--update] [-p] [-P PUBLIC_KEY] PRIVATE_KEY [TITLE]'
        return 2
        ;;
      *)
        break
        ;;
    esac
  done

  if (($# < 1 || $# > 2)); then
    print -u2 -- \
      'usage: pp-ssh-import [--update] [-p] [-P PUBLIC_KEY] PRIVATE_KEY [TITLE]'
    return 2
  fi

  _pp_ssh_require pass-cli ssh-keygen awk mktemp jq

  local private_file=${1:A}
  local title=${2:-${private_file:t}}
  local vault=$(_pp_ssh_vault)
  local tmpdir normalized_private derived_public public_file
  local protected key_type item_count
  local ref share_id item_id
  local -a args

  if [[ ! -f $private_file ]]; then
    print -u2 -- "not a regular file: $private_file"
    return 1
  fi

  item_count=$(_pp_ssh_item_count "$title" "$vault")

  if ((item_count > 1)); then
    print -u2 -- \
      "multiple active SSH items are named '$title' in vault '$vault'"
    print -u2 -- \
      'remove or rename the duplicate before using title-based commands'
    return 1
  fi

  if ((item_count == 1 && !update)); then
    print -u2 -- "SSH key already exists: $title"
    print -u2 -- \
      "use: pp-ssh-import --update ${(q)private_file} ${(q)title}"
    return 1
  fi

  if ((item_count == 0 && update)); then
    print -u2 -- "SSH key does not exist: $title"
    print -u2 -- 'omit --update to create it'
    return 1
  fi

  if ((update)); then
    ref=$(_pp_ssh_resolve_item "$title" "$vault")
    IFS=$'\t' read -r share_id item_id <<<"$ref"
  fi

  if [[ -z $supplied_public && -f ${private_file}.pub ]]; then
    supplied_public=${private_file}.pub
  fi

  tmpdir=$(_pp_ssh_tmpdir)
  normalized_private=$tmpdir/private
  derived_public=$tmpdir/derived-public
  public_file=$tmpdir/public

  (
    trap '
      rc=$?
      command rm -rf -- "$tmpdir"
      exit "$rc"
    ' EXIT

    _pp_ssh_normalize_private_file \
      "$private_file" \
      "$normalized_private"

    # Validate the exact normalized copy that will be sent to pass-cli.
    _pp_ssh_derive_public "$normalized_private" >|"$derived_public"

    protected=$(_pp_ssh_private_is_protected "$normalized_private")
    ((force_password)) && protected=true

    if [[ -n $supplied_public ]]; then
      if [[ ! -f $supplied_public ]]; then
        print -u2 -- "not a regular file: $supplied_public"
        return 1
      fi

      _pp_ssh_validate_public_files "$derived_public" "$supplied_public"
      _pp_ssh_public_line <"$supplied_public" >|"$public_file"
    else
      command cat -- "$derived_public" >|"$public_file"
    fi

    key_type=$(_pp_ssh_detect_key_type "$public_file")

    if ((update)); then
      _pp_ssh_update_item \
        "$share_id" \
        "$item_id" \
        "$normalized_private" \
        "$public_file" \
        updated \
        "$key_type" \
        "$protected"

      _pp_ssh_verify_stored_public \
        "$share_id" \
        "$item_id" \
        "$title" \
        "$public_file"
      print -r -- "updated SSH key: $title"
    else
      args=(
        item create ssh-key import
        --vault-name "$vault"
        --title "$title"
        --from-private-key "$normalized_private"
      )

      [[ $protected == true ]] && args+=(--password)

      item_id=$(command pass-cli "${args[@]}")

      if [[ -z $item_id ]]; then
        print -u2 -- 'pass-cli did not return an item ID'
        return 1
      fi

      ref=$(_pp_ssh_created_item_ref "$item_id" "$vault")
      IFS=$'\t' read -r share_id item_id <<<"$ref"

      _pp_ssh_set_metadata \
        "$share_id" \
        "$item_id" \
        imported \
        "$key_type" \
        "$protected"

      _pp_ssh_verify_stored_public \
        "$share_id" \
        "$item_id" \
        "$title" \
        "$public_file"
      print -r -- "imported SSH key: $title"
    fi
  ) || return $?
}

pp-ssh-export() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn pipefail

  local force=0

  if [[ ${1:-} == -f || ${1:-} == --force ]]; then
    force=1
    shift
  fi

  if (($# < 1 || $# > 2)); then
    print -u2 -- 'usage: pp-ssh-export [-f|--force] TITLE [DESTINATION]'
    return 2
  fi

  _pp_ssh_require pass-cli jq ssh-keygen awk mktemp

  local title=$1
  local vault=$(_pp_ssh_vault)
  local destination
  local ref share_id item_id
  local tmpdir private_file public_file

  if (($# == 2)); then
    destination=${2:A}
  else
    if [[ $title == */* ]]; then
      print -u2 -- 'TITLE contains a slash; specify DESTINATION explicitly'
      return 2
    fi

    destination=${HOME:A}/.ssh/$title
  fi

  ref=$(_pp_ssh_resolve_item "$title" "$vault")
  IFS=$'\t' read -r share_id item_id <<<"$ref"

  tmpdir=$(_pp_ssh_tmpdir)
  private_file=$tmpdir/private
  public_file=$tmpdir/public

  (
    trap '
      rc=$?
      command rm -rf -- "$tmpdir"
      exit "$rc"
    ' EXIT

    _pp_ssh_field "$share_id" "$item_id" private_key >|"$private_file"
    command chmod 600 "$private_file"

    _pp_ssh_field "$share_id" "$item_id" public_key \
      | _pp_ssh_public_line >|"$public_file"
    command chmod 644 "$public_file"

    _pp_ssh_validate_pair "$private_file" "$public_file"
    _pp_ssh_write_pair "$force" "$private_file" "$public_file" "$destination"
  ) || return $?
}

pp-ssh-update() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn pipefail

  local supplied_public=
  local OPTIND=1 opt

  while getopts ':P:' opt; do
    case $opt in
      P) supplied_public=${OPTARG:A} ;;
      *)
        print -u2 -- \
          'usage: pp-ssh-update [-P PUBLIC_KEY] TITLE PRIVATE_KEY'
        return 2
        ;;
    esac
  done

  shift $((OPTIND - 1))

  if (($# != 2)); then
    print -u2 -- \
      'usage: pp-ssh-update [-P PUBLIC_KEY] TITLE PRIVATE_KEY'
    return 2
  fi

  _pp_ssh_require pass-cli jq ssh-keygen awk mktemp

  local title=$1
  local private_file=${2:A}
  local vault=$(_pp_ssh_vault)
  local ref share_id item_id
  local tmpdir derived_public public_file
  local protected key_type

  if [[ ! -f $private_file ]]; then
    print -u2 -- "not a regular file: $private_file"
    return 1
  fi

  ref=$(_pp_ssh_resolve_item "$title" "$vault")
  IFS=$'\t' read -r share_id item_id <<<"$ref"

  if [[ -z $supplied_public && -f ${private_file}.pub ]]; then
    supplied_public=${private_file}.pub
  fi

  protected=$(_pp_ssh_private_is_protected "$private_file")

  tmpdir=$(_pp_ssh_tmpdir)
  derived_public=$tmpdir/derived-public
  public_file=$tmpdir/public

  (
    trap '
      rc=$?
      command rm -rf -- "$tmpdir"
      exit "$rc"
    ' EXIT

    _pp_ssh_derive_public "$private_file" >|"$derived_public"

    if [[ -n $supplied_public ]]; then
      if [[ ! -f $supplied_public ]]; then
        print -u2 -- "not a regular file: $supplied_public"
        return 1
      fi

      _pp_ssh_validate_public_files "$derived_public" "$supplied_public"
      _pp_ssh_public_line <"$supplied_public" >|"$public_file"
    else
      command cat -- "$derived_public" >|"$public_file"
    fi

    key_type=$(_pp_ssh_detect_key_type "$public_file")

    _pp_ssh_update_item \
      "$share_id" \
      "$item_id" \
      "$private_file" \
      "$public_file" \
      updated \
      "$key_type" \
      "$protected"

    _pp_ssh_verify_stored_public \
      "$share_id" \
      "$item_id" \
      "$title" \
      "$public_file"
    print -r -- "updated SSH key: $title"
  ) || return $?
}

pp-ssh-rotate() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn

  local key_type=ed25519
  local comment=
  local destination=
  local force=0
  local use_password=0
  local OPTIND=1 opt

  while getopts ':fpt:C:o:' opt; do
    case $opt in
      f) force=1 ;;
      p) use_password=1 ;;
      t) key_type=$OPTARG ;;
      C) comment=$OPTARG ;;
      o) destination=${OPTARG:A} ;;
      *)
        print -u2 -- \
          'usage: pp-ssh-rotate [-f] [-p] [-t TYPE] [-C COMMENT] [-o DEST] TITLE'
        return 2
        ;;
    esac
  done

  shift $((OPTIND - 1))

  if (($# != 1)); then
    print -u2 -- \
      'usage: pp-ssh-rotate [-f] [-p] [-t TYPE] [-C COMMENT] [-o DEST] TITLE'
    return 2
  fi

  case $key_type in
    ed25519 | rsa2048 | rsa4096) ;;
    *)
      print -u2 -- "unsupported key type: $key_type"
      return 2
      ;;
  esac

  _pp_ssh_require pass-cli jq ssh-keygen awk mktemp

  local title=$1
  local vault=$(_pp_ssh_vault)
  local ref share_id item_id
  local tmpdir private_file public_file
  local protected=false
  local -a keygen_args export_args

  ref=$(_pp_ssh_resolve_item "$title" "$vault")
  IFS=$'\t' read -r share_id item_id <<<"$ref"

  [[ -n $comment ]] || comment=$title
  ((use_password)) && protected=true

  tmpdir=$(_pp_ssh_tmpdir)
  private_file=$tmpdir/private
  public_file=${private_file}.pub

  case $key_type in
    ed25519)
      keygen_args=(-t ed25519)
      ;;
    rsa2048)
      keygen_args=(-t rsa -b 2048)
      ;;
    rsa4096)
      keygen_args=(-t rsa -b 4096)
      ;;
  esac

  (
    trap '
      rc=$?
      command rm -rf -- "$tmpdir"
      exit "$rc"
    ' EXIT

    if ((use_password)); then
      command ssh-keygen \
        -q \
        "${keygen_args[@]}" \
        -C "$comment" \
        -f "$private_file"
    else
      command ssh-keygen \
        -q \
        "${keygen_args[@]}" \
        -N '' \
        -C "$comment" \
        -f "$private_file"
    fi

    _pp_ssh_update_item \
      "$share_id" \
      "$item_id" \
      "$private_file" \
      "$public_file" \
      rotated \
      "$key_type" \
      "$protected"

    _pp_ssh_verify_stored_public \
      "$share_id" \
      "$item_id" \
      "$title" \
      "$public_file"

    print -r -- "rotated SSH key: $title"
    print -r -- 'new public key:'
    command cat -- "$public_file"

    if [[ -n $destination ]]; then
      export_args=()
      ((force)) && export_args+=(--force)
      export_args+=("$title" "$destination")
      pp-ssh-export "${export_args[@]}"
    fi
  ) || return $?
}

pp-ssh-status() {
  emulate -L zsh
  unsetopt xtrace
  setopt localoptions errreturn pipefail

  if (($# < 1 || $# > 2)); then
    print -u2 -- 'usage: pp-ssh-status TITLE [PRIVATE_KEY]'
    return 2
  fi

  _pp_ssh_require pass-cli jq ssh-keygen awk

  local title=$1
  local vault=$(_pp_ssh_vault)
  local private_file
  local ref share_id item_id
  local local_identity stored_identity

  if (($# == 2)); then
    private_file=${2:A}
  else
    if [[ $title == */* ]]; then
      print -u2 -- 'TITLE contains a slash; specify PRIVATE_KEY explicitly'
      return 2
    fi

    private_file=${HOME:A}/.ssh/$title
  fi

  if [[ ! -f $private_file ]]; then
    print -u2 -- "not a regular file: $private_file"
    return 1
  fi

  ref=$(_pp_ssh_resolve_item "$title" "$vault")
  IFS=$'\t' read -r share_id item_id <<<"$ref"

  local_identity=$(
    _pp_ssh_derive_public "$private_file" \
      | _pp_ssh_public_identity
  )

  stored_identity=$(
    _pp_ssh_field "$share_id" "$item_id" public_key \
      | _pp_ssh_public_identity
  )

  if [[ -z $local_identity || -z $stored_identity ]]; then
    print -u2 -- 'could not derive one or both public key identities'
    return 1
  fi

  if [[ $local_identity == $stored_identity ]]; then
    print -r -- "local key matches Proton Pass: $title"
    return 0
  fi

  print -u2 -- "local key differs from Proton Pass: $title"
  return 1
}
