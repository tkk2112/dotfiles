#!/bin/sh
set -eu

if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
  set -x
fi

repo_root="${DOTFILES_LOCATION:-${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}}"
profiles="${DOTFILES_PROFILES:-workstation,development,owned}"
package_mode="${DOTFILES_CI_PACKAGE_MODE:-native}"
ci_user="dotfiles"
ci_home="/home/$ci_user"
brew_prefix="/home/linuxbrew/.linuxbrew"
base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

log() {
  printf '%s\n' "$*"
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

section() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

install_linux_harness() {
  section "Installing CI harness dependencies"

  if command -v apt-get >/dev/null 2>&1; then
    run apt-get update
    run env DEBIAN_FRONTEND=noninteractive \
      apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      curl \
      file \
      git \
      passwd \
      procps \
      sudo \
      util-linux
  elif command -v dnf >/dev/null 2>&1; then
    run dnf install -y \
      bash \
      ca-certificates \
      curl \
      file \
      findutils \
      gcc \
      gcc-c++ \
      git \
      make \
      procps-ng \
      shadow-utils \
      sudo \
      util-linux
  elif command -v pacman >/dev/null 2>&1; then
    run pacman -Syu --noconfirm --needed \
      base-devel \
      bash \
      ca-certificates \
      curl \
      file \
      git \
      procps-ng \
      shadow \
      sudo \
      util-linux
  else
    fail "unsupported Linux package manager"
  fi
}

create_ci_user() {
  section "Creating unprivileged install user"

  if ! id "$ci_user" >/dev/null 2>&1; then
    run useradd --create-home --shell /bin/bash "$ci_user"
  fi

  run mkdir -p "$ci_home"
  run chown -R "$ci_user:$ci_user" "$ci_home"

  # Chezmoi invokes Git while running as ci_user, so the disposable CI
  # checkout must be owned by that user.
  run chown -R "$ci_user:$ci_user" "$repo_root"
}

configure_native_access() {
  section "Allowing native package installation"

  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$ci_user" \
    >"/etc/sudoers.d/$ci_user"

  chmod 0440 "/etc/sudoers.d/$ci_user"
}

prepare_linuxbrew_cache() {
  if [ -z "${HOMEBREW_CACHE:-}" ]; then
    return 0
  fi

  section "Preparing Homebrew download cache"

  run mkdir -p "$HOMEBREW_CACHE"
  run chown -R "$ci_user:$ci_user" "$HOMEBREW_CACHE"
}

run_as_ci_user() {
  run runuser -u "$ci_user" -- env \
    HOME="$ci_home" \
    USER="$ci_user" \
    LOGNAME="$ci_user" \
    SHELL=/bin/bash \
    PATH="$ci_path" \
    "$@"
}

ci_user_has() {
  runuser -u "$ci_user" -- env \
    HOME="$ci_home" \
    USER="$ci_user" \
    LOGNAME="$ci_user" \
    SHELL=/bin/bash \
    PATH="$ci_path" \
    sh -c "command -v \"$1\" >/dev/null 2>&1"
}

install_linuxbrew() {
  prepare_linuxbrew_cache

  section "Installing Linuxbrew"

  run mkdir -p "$brew_prefix"
  run chown -R "$ci_user:$ci_user" /home/linuxbrew

  run curl -fsSL \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
    -o /tmp/install-homebrew.sh

  run chmod 0755 /tmp/install-homebrew.sh

  run_as_ci_user env \
    NONINTERACTIVE=1 \
    CI=1 \
    HOMEBREW_NO_ANALYTICS=1 \
    /bin/bash /tmp/install-homebrew.sh

  ci_path="$brew_prefix/bin:$brew_prefix/sbin:$ci_path"

  run_as_ci_user brew --version
}

validate_linux_profile() {
  if ! ci_user_has jq; then
    log "Skipping selected profile validation because jq is unavailable"
    return 0
  fi

  section "Validating selected profile"

  run_as_ci_user env \
    DOTFILES_CI=true \
    DOTFILES_LOCATION="$repo_root" \
    DOTFILES_PROFILE_SET="$profiles" \
    sh "$repo_root/scripts/test-profiles.sh"
}

run_linux_install() {
  install_linux_harness
  create_ci_user

  ci_path="$ci_home/.local/bin:$base_path"
  disable_homebrew=0
  expect_packages=true

  case "$package_mode" in
    native)
      case ",$profiles," in
        *,owned,*) ;;
        *) fail "native package mode requires the owned profile" ;;
      esac

      configure_native_access
      disable_homebrew=1
      ;;

    native-linuxbrew)
      case ",$profiles," in
        *,owned,*) ;;
        *) fail "native-linuxbrew package mode requires the owned profile" ;;
      esac

      configure_native_access
      install_linuxbrew
      ;;

    linuxbrew)
      case ",$profiles," in
        *,owned,*)
          fail "linuxbrew package mode must not use the owned profile"
          ;;
        *) ;;
      esac

      install_linuxbrew
      ;;

    degraded)
      case ",$profiles," in
        *,owned,*)
          fail "degraded package mode must not use the owned profile"
          ;;
        *) ;;
      esac

      disable_homebrew=1
      expect_packages=false
      ;;

    *)
      fail "unknown DOTFILES_CI_PACKAGE_MODE: $package_mode"
      ;;
  esac

  section "Running actual dotfiles install"

  run_as_ci_user env \
    DOTFILES_CI=true \
    DOTFILES_LOCATION="$repo_root" \
    DOTFILES_PROFILES="$profiles" \
    DOTFILES_CI_PACKAGE_MODE="$package_mode" \
    DOTFILES_DISABLE_HOMEBREW="$disable_homebrew" \
    DOTFILES_CI_EXPECT_PACKAGES="$expect_packages" \
    GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    sh "$repo_root/setup.sh"

  section "Checking package path"

  case "$package_mode" in
    native)
      if ci_user_has brew; then
        fail "native package test unexpectedly exposed Homebrew"
      fi

      ci_user_has jq \
        || fail "native package install did not provide jq"
      ci_user_has nvim \
        || fail "native package install did not provide nvim"
      ;;

    native-linuxbrew)
      ci_user_has brew \
        || fail "owned Linuxbrew supplement test cannot find brew"
     ÚWİ\Ù\—Ú\ÈœHˆ˜Z[›˜]]™HXÚØYÙH[œİ[Y›İ›İšYHœH‚ˆÚWİ\Ù\—Ú\Èš[Hˆ˜Z[›˜]]™HXÚØYÙH[œİ[Y›İ›İšYHš[H‚ˆÚWİ\Ù\—Ú\È\ÜËXÛHˆ˜Z[›İÛ™Y[^œ™]Èİ\[Y[ÈY›İ›İšYH\ÜËXÛH‚ˆÎÂ‚ˆ[^œ™]ÊBˆÚWİ\Ù\—Ú\Èœ™]Èˆ˜Z[“[^œ™]ÈXÚØYÙH\İØ[››İš[™œ™]È‚ˆÚWİ\Ù\—Ú\ÈœHˆ˜Z[“[^œ™]ÈXÚØYÙH[œİ[Y›İ›İšYHœH‚ˆÚWİ\Ù\—Ú\ÈÙˆ˜Z[“[^œ™]ÈXÚØYÙH[œİ[Y›İ›İšYHÙ‚ˆ6•÷W6W%ö†2çf–ÒÀ¢ÇÂf–Â$Æ–çW†'&Wr6¶vR–ç7FÆÂF–Bæ÷B&÷f–FRçf–Ò ¢³° ¢FVw&FVB¢–b6•÷W6W%ö†2'&Ws²F†Và¢f–Â&FVw&FVB6¶vRFW7BVæW‡V7FVFÇ’W‡÷6VB†öÖV'&Wr ¢f¢³°¢W60 ¢6V7F–öâ%'Vææ–ær–ç7FÆÂfÆ–FF–öâ  ¢'Våö5ö6•÷W6W"VçbÀ¢DõDd”ÄU5ô4“×G'VRÀ¢DõDd”ÄU5ôÄô4D”ôãÒ"G&Wõ÷&ö÷B"À¢DõDd”ÄU5õ$ôd”ÄU3Ò"G&öf–ÆW2"À¢DõDd”ÄU5ô4•õ4´tUôÔôDSÒ"G6¶vUöÖöFR"À¢DõDd”ÄU5ô4•ôU…T5Eõ4´tU3Ò"FW‡V7E÷6¶vW2"À¢6‚"G&Wõ÷&ö÷B÷67&—G2÷FW7BÖ–ç7FÆÂç6‚  ¢fÆ–FFUöÆ–çW…÷&öf–ÆP§Ğ §fÆ–FFUöÖ6÷5÷&öf–ÆR‚’°¢6V7F–öâ%fÆ–FF–ær6VÆV7FVB&öf–ÆR  ¢'VâVçbÀ¢DõDd”ÄU5ô4“×G'VRÀ¢DõDd”ÄU5ôÄô4D”ôãÒ"G&Wõ÷&ö÷B"À¢DõDd”ÄU5õ$ôd”ÄUõ4UCÒ"G&öf–ÆW2"À¢6‚"G&Wõ÷&ö÷B÷67&—G2÷FW7B×&öf–ÆW2ç6‚ §Ğ §'VåöÖ6÷5ö–ç7FÆÂ‚’°¢²"G6¶vUöÖöFR"Ò&'&Wr"ÒÀ¢ÇÂf–Â&Ö4õ24’&WV—&W2DõDd”ÄU5ô4•õ4´tUôÔôDSÖ'&Wr  ¢–b²Öâ"G´„ôÔT%$Uuô44„S¢×Ò"Ó²F†Và¢'VâÖ¶F—"×"D„ôÔT%$Uuô44„R ¢f ¢W‡÷'BDõDd”ÄU5ô4“×G'VP¢W‡÷'BDõDd”ÄU5ôÄô4D”ôãÒ"G&Wõ÷&ö÷B ¢W‡÷'BDõDd”ÄU5õ$ôd”ÄU3Ò"G&öf–ÆW2 ¢W‡÷'BDõDd”ÄU5ô4•õ4´tUôÔôDSÒ"G6¶vUöÖöFR ¢W‡÷'BDõDd”ÄU5ô4•ôU…T5Eõ4´tU3×G'VP¢W‡÷'B„ôÔT%$UuôäõôäÅ•D”53Ó¢W‡÷'B„ôÔT%$UuôäõôUDõõUDDSÓ¢W‡÷'BDƒÒ"D„ôÔRòæÆö6Âö&–ã¢ED‚  ¢6V7F–öâ%'Vææ–ær7GVÂF÷Ff–ÆW2–ç7FÆÂ  ¢'Vâ6‚"G&Wõ÷&ö÷B÷6WGWç6‚  ¢6V7F–öâ$6†V6¶–ær†öÖV'&Wr6¶vRF‚  ¢6öÖÖæB×b'&WrâöFWböçVÆÂ#âcÀ¢ÇÂf–Â$†öÖV'&Wr—2Væf–Æ&ÆR ¢6öÖÖæB×b§âöFWböçVÆÂ#âcÀ¢ÇÂf–Â$†öÖV'&Wr6¶vR–ç7FÆÂF–Bæ÷B&÷f–FR§ ¢6öÖÖæB×bÇ6BâöFWböçVÆÂ#âcÀ¢ÇÂf–Â$†öÖV'&Wr6¶vR–ç7FÆÂF–Bæ÷B&÷f–FRÇ6B ¢6öÖÖæB×bçf–ÒâöFWböçVÆÂ#âcÀ¢ÇÂf–Â$†öÖV'&Wr6¶vR–ç7FÆÂF–Bæ÷B&÷f–FRçf–Ò  ¢6V7F–öâ%'Vææ–ær–ç7FÆÂfÆ–FF–öâ  ¢'Vâ6‚"G&Wõ÷&ö÷B÷67&—G2÷FW7BÖ–ç7FÆÂç6‚  ¢fÆ–FFUöÖ6÷5÷&öf–ÆP§Ğ ¦Æör%7F'F–ær4’F÷Ff–ÆW2–ç7FÆÂ ¦Æör$„ôÔSÒD„ôÔR ¦Æör%tCÒEtB ¦Æör$DõDd”ÄU5ôÄô4D”ôãÒG&Wõ÷&ö÷B ¦Æör$DõDd”ÄU5õ$ôd”ÄU3ÒG&öf–ÆW2 ¦Æör$DõDd”ÄU5ô4•õ4´tUôÔôDSÒG6¶vUöÖöFR ¦Æör%DƒÒED‚  ¦–b²ÖböWF2ö÷2×&VÆV6RÓ²F†Và¢Æör" ¢Æör"öWF2ö÷2×&VÆV6S¢ ¢6BöWF2ö÷2×&VÆV6P¦f ¦66R"B‡VæÖR×2’"–à¢F'v–â¢'VåöÖ6÷5ö–ç7FÆÀ¢³°¢Æ–çW‚¢'VåöÆ–çW…ö–ç7FÆÀ¢³°¢¢¢f–Â'Vç7W÷'FVB÷W&F–ær7—7FVÓ¢B‡VæÖR×2’ ¢³°¦W60 