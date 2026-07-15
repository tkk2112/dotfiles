# dotfiles

![ci status](https://github.com/tkk2112/dotfiles/actions/workflows/main.yml/badge.svg)

Chezmoi-managed shell, terminal, editor, SSH, and development configuration.

## Install

```sh
curl -LsSf https://raw.githubusercontent.com/tkk2112/dotfiles/refs/heads/main/setup.sh | sh
```

Run from a checkout to use it as the chezmoi source:

```sh
./setup.sh
```

Set `DOTFILES_PROFILES` to skip the interactive profile prompt:

```sh
DOTFILES_PROFILES=workstation,laptop,development,owned ./setup.sh
```

Select exactly one machine role: `workstation` or `headless`. Optional capability profiles are `development`, `gaming`, `server`, `laptop`, and `owned`.

## Maintenance

Apply upstream changes with `chezmoi update`. Apply local source changes with `chezmoi apply`.

Run repository checks with:

```sh
uv tool run pre-commit run --all-files
```
