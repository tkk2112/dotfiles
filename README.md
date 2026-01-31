# dotfiles
![ci status](https://github.com/tkk2112/dotfiles/actions/workflows/main.yml/badge.svg)

chezmoi-managed user dotfiles.

Bootstrap:

```sh
curl -LsSf https://raw.githubusercontent.com/tkk2112/dotfiles/refs/heads/main/setup.sh | sh
```

Local apply from a checkout:

```sh
./setup.sh
```

After bootstrap, update machines with `chezmoi update`.

