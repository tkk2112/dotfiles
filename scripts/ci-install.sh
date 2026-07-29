#!/bin/sh
set -eu

if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
  set -x
fi

repo_root="${DOTFILES_LOCATION:-${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}}"
profiles="${DOTFILES_PROFILES:-workstation,development,owned}"
package_mode="${DOTFILES_CI_PACKAGE_MODE:-native}"
profile_scope="${DOTFILES_PROFILE_SCOPE:-selected}"
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

case "$profile_scope" in
  selected | all) ;;
  *) fail "unknown DOTFILES_PROFILE_SCOPE: $profile_scope" ;;
esac

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
    run pacman -Sy --noconfirm --needed \
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

  # GitHub mounts the checkout outside the test user's home. The source only
  # needs to be readable; all generated state is written below ci_home.
  run chmod -R a+rX "$repo_root"
}

configure_native_access() {
  section "Allowing native package installation"

  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$ci_user" \
    >"/etc/sudoers.d/$ci_user"

  chmod 0440 "/etc/sudoers.d/$ci_user"
}

install_linuxbrew() {
  section "Installing Linuxbrew for the unowned-machine path"

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

validate_linux_profiles() {
  if ! ci_user_has jq; then
    log "Skipping profile renderer validation because jq is unavailable"
    return 0
  fi

  section "Validating rendered profiles"

  if [ "$profile_scope" = "all" ]; then
    run_as_ci_user env \
      DOTFILES_CI=true \
      DOTFILES_LOCATION="$repo_root" \
      DOTFILES_PROFILE_SCOPE=all \
      sh "$repo_root/scripts/test-profiles.sh"
  else
    run_as_ci_user env \
      DOTFILES_CI=true \
      DOTFILES_LOCATION="$repo_root" \
      DOTFILES_PROFILE_SET="$profiles" \
      sh "$repo_root/scripts/test-profiles.sh"
  fi
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

    linuxbrew)
      ci_user_has brew \
        || fail "Linuxbrew package test cannot find brew"
      ci_user_has jq \
        || fail "Linuxbrew package install did not provide jq"
      ci_user_has lsd \
        || fail "Linuxbrew package install did not provide lsd"
      ci_user_has nvim \
        || fail "Linuxbrew package install did not provide nvim"
      ;;

    degraded)
      if ci_user_has brew; then
        fail "degraded package test unexpectedly exposed Homebrew"
      fi
      ;;
  esac

  section "Running install validation"

  run_as_ci_user env \
    DOTFILES_CI=true \
    DOTFILES_LOCATION="$repo_root" \
    DOTFILES_PROFILES="$profiles" \
    DOTFILES_CI_PACKAGE_MODE="$package_mode" \
    DOTFILES_CI_EXPECT_PACKAGES="$expect_packages" \
    sh "$repo_root/scripts/test-install.sh"

  validate_linux_profiles
}

validate_macos_profiles() {
  section "Validating rendered profiles"

  if [ "$profile_scope" = "all" ]; then
    run env \
      DOTFILES_CI=true \
      DOTFILES_LOCATION="$repo_root" \
      DOTFILES_PROFILE_SCOPE=all \
      sh "$repo_root/scripts/test-profiles.sh"
  else
    run env \
      DOTFILES_CI=true \
      DOTFILES_LOCATION="$repo_root" \
      DOTFILES_PROFILE_SET="$profiles" \
      sh "$repo_root/scripts/test-profiles.sh"
  fi
}

run_macos_install() {
  [ "$package_mode" = "brew" ] \
    || fail "macOS CI requires DOTFILES_CI_PACKAGE_MODE=brew"

  export DOTFILES_CI=true
  export DOTFILES_LOCATION="$repo_root"
  export DOTFILES_PROFILES="$profiles"
  export DOTFILES_CI_PACKAGE_MODE="$package_mode"
  export DOTFILES_CI_EXPECT_PACKAGES=true
  export HOMEBREW_NO_ANALYTICS=1
  export HOMEBREW_NO_AUTO_UPDATE=1
  export PATH="$HOME/.local/bin:$PATH"

  section "Running actual dotfiles install"

  run sh "$repo_root/setup.sh"

  section "Checking Homebrew package path"

  command -v brew >/dev/null 2>&1 \
    || fail "Homebrew is unavailable"
  command -v jq >/dev/null 2>&1 \
    || fail "Homebrew package install did not provide jq"
  command -v lsd >/dev/null 2>&1 \
    || fail "Homebrew package install did not provide lsd"
  command -v nvim >/dev/null 2>&1 \
    || fail "Homebrew package install did not provide nvim"

  section "Running install validation"

  run sh "$repo_root/scripts/test-install.sh"

  validate_macos_profiles
}

log "Starting CI dotfiles install"
log "HOME=$HOME"
log "PWD=$PWD"
log "DOTFILES_LOCATION=$repo_root"
log "DOTFILES_PROFILES=$profiles"
log "DOTFILES_CI_PACKAGE_MODE=$package_mode"
log "DOTFILES_PROFILE_SCOPE=$profile_scope"
log "PATH=$PATH"

if [ -f /etc/os-release ]; then
  log ""
  log "/etc/os-release:"
  cat /etc/os-release
fi

case "$(uname -s)" in
  Darwin)
    run_macos_install
    ;;
  Linux)
    run_linux_install
    ;;
  *)
    fail "unsupported operating system: $(uname -s)"
    ;;
esac
