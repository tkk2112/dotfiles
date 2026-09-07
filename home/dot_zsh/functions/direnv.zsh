# Some Zsh completion functions temporarily change directory while gathering
# matches. Ignore those directory changes so direnv does not unload/reload the
# environment as a side effect of tab completion.
if (($+functions[_direnv_hook] && !$+functions[_dotfiles_direnv_hook])); then
  functions -c _direnv_hook _dotfiles_direnv_hook
fi

if (($+functions[_dotfiles_direnv_hook])); then
  _direnv_hook() {
    [[ -n ${compstate[context]:-} ]] && return 0

    _dotfiles_direnv_hook "$@"
  }
fi
