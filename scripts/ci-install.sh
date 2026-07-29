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
    HOMEBREW_CACHE="${HOMEBREW_CACHE:-}" \
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
      ci_user_has jq \
        || fail "native package install did not provide jq"
      ci_user_has nvim \
        || fail "native package install did not provide nvim"
      ci_user_has pass-cli \
        || fail "owned Linuxbrew supplements did not provide pass-cli"
      ;;

    linuxbrew)
      ci_user_has brew \
        || fail "Linuxbrew package test cannot find brew"
      ci_user_has jq \
        || fail "Linuxbrew package install did not provide jq"
     ÚWİ\Ù\—Ú\ÈÙˆ˜Z[“[^œ™]ÈXÚØYÙH[œİ[Y›İ›İšYHÙ‚ˆÚWİ\Ù\—Ú\Èš[Hˆ˜Z[“[^œ™]ÈXÚØYÙH[œİ[Y›İ›İšYHš[H‚ˆÎÂ‚ˆYÜ˜YY
BˆYˆÚWİ\Ù\—Ú\Èœ™]ÎÈ[‚ˆ˜Z[™YÜ˜YYXÚØYÙH\İ[™^XİYH^ÜÙYÛYXœ™]È‚ˆšBˆÎÂˆ\ØXÂ‚ˆÙXİ[Ûˆ”[›š[™È[œİ[˜[Y][Ûˆ‚‚ˆ[—Ø\×ØÚWİ\Ù\ˆ[ˆˆÕ’ST×ĞÒO]YHˆÕ’ST×ÓĞĞUSÓH‰™\×Ü›ÛİˆˆÕ’ST×Ô“Ñ’STÏH‰›Ùš[\ÈˆˆÕ’ST×ĞÒWÔPÒĞQÑWÓSÑOH‰XÚØYÙWÛ[ÙHˆˆÕ’ST×ĞÒWÑVPÕÔPÒĞQÑTÏH‰^XİÜXÚØYÙ\ÈˆˆÚ‰™\×Ü›ÛİÜØÜš\Ëİ\İZ[œİ[œÚ‚‚ˆ˜[Y]WÛ[^Ü›Ùš[BŸB‚˜[Y]WÛXXÛÜ×Ü›Ùš[J
HÂˆÙXİ[Ûˆ•˜[Y][™ÈÙ[XİY›Ùš[H‚‚ˆ[ˆ[ˆˆÕ’ST×ĞÒO]YHˆÕ’ST×ÓĞĞUSÓH‰™\×Ü›ÛİˆˆÕ’ST×Ô“Ñ’SWÔÑUH‰›Ùš[\ÈˆˆÚ‰™\×Ü›ÛİÜØÜš\Ëİ\İ\›Ùš[\ËœÚ‚ŸB‚œ[—ÛXXÛÜ×Ú[œİ[

HÂˆÈ‰XÚØYÙWÛ[ÙHˆH˜œ™]ÈˆHˆ˜Z[›XXÓÔÈÒH™\]Z\™\ÈÕ’ST×ĞÒWÔPÒĞQÑWÓSÑOXœ™]È‚‚ˆYˆÈ[ˆ‰ÒÓQP”‘U×ĞĞPÒN‹_HˆNÈ[‚ˆ[ˆZÙ\ˆ\‰ÓQP”‘U×ĞĞPÒH‚ˆšB‚ˆ^ÜÕ’ST×ĞÒO]YBˆ^ÜÕ’ST×ÓĞĞUSÓH‰™\×Ü›Ûİ‚ˆ^ÜÕ’ST×Ô“Ñ’STÏH‰›Ùš[\È‚ˆ^ÜÕ’ST×ĞÒWÔPÒĞQÑWÓSÑOH‰XÚØYÙWÛ[ÙH‚ˆ^ÜÕ’ST×ĞÒWÑVPÕÔPÒĞQÑTÏ]YBˆ^ÜÓQP”‘U×Ó“×ĞSSUPÔÏLBˆ^ÜÓQP”‘U×Ó“×ĞUU×ÕTUOLBˆ^ÜUH‰ÓQKË›ØØ[Øš[‰U‚‚ˆÙXİ[Ûˆ”[›š[™ÈXİX[İš[\È[œİ[‚‚ˆ[ˆÚ‰™\×Ü›ÛİÜÙ]\œÚ‚‚ˆÙXİ[ÛˆÚXÚÚ[™ÈÛYXœ™]ÈXÚØYÙH]‚‚ˆÛÛ[X[™]ˆœ™]È‹Ù]‹Û[‰ŒHˆ˜Z[’ÛYXœ™]È\È[˜]˜Z[X›H‚ˆÛÛ[X[™]ˆœH‹Ù]‹Û[‰ŒHˆ˜Z[’ÛYXœ™]ÈXÚØYÙH[œİ[Y›İ›İšYHœH‚ˆÛÛ[X[™]ˆÙ‹Ù]‹Û[‰ŒHˆ˜Z[’ÛYXœ™]ÈXÚØYÙH[œİ[Y›İ›İšYHÙ‚ˆÛÛ[X[™]ˆš[H‹Ù]‹Û[‰ŒHˆ˜Z[’ÛYXœ™]ÈXÚØYÙH[œİ[Y›İ›İšYHš[H‚‚ˆÙXİ[Ûˆ”[›š[™È[œİ[˜[Y][Ûˆ‚‚ˆ[ˆÚ‰™\×Ü›ÛİÜØÜš\Ëİ\İZ[œİ[œÚ‚‚ˆ˜[Y]WÛXXÛÜ×Ü›Ùš[BŸB‚›ÙÈ”İ\[™ÈÒHİš[\È[œİ[‚›ÙÈ’ÓQOIÓQH‚›ÙÈ”ÑIÑ‚›ÙÈ‘Õ’ST×ÓĞĞUSÓI™\×Ü›Ûİ‚›ÙÈ‘Õ’ST×Ô“Ñ’STÏI›Ùš[\È‚›ÙÈ‘Õ’ST×ĞÒWÔPÒĞQÑWÓSÑOIXÚØYÙWÛ[ÙH‚›ÙÈ”UIU‚‚šYˆÈYˆÙ]ËÛÜË\™[X\ÙHNÈ[‚ˆÙÈˆ‚ˆÙÈ‹Ù]ËÛÜË\™[X\ÙNˆ‚ˆØ]Ù]ËÛÜË\™[X\ÙB™šB‚˜Ø\ÙH‰
[˜[YH\ÊHˆ[‚ˆ\Ú[ŠBˆ[—ÛXXÛÜ×Ú[œİ[ˆÎÂˆ[^
Bˆ[—Û[^Ú[œİ[ˆÎÂˆ
ŠBˆ˜Z[[œİ\ÜYÜ\˜][™ÈŞ\İ[Nˆ	
[˜[YH\ÊH‚ˆÎÂ™\ØXÂ