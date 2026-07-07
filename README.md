# dotfiles
![ci status](https://github.com/tkk2112/dotfiles/actions/workflows/main.yml/badge.svg)

chezmoi-managed user dotfiles.

Bootstrap:

```sh
curl -LsSf https://link.m04r.space/dotfiles | sh
```

Local apply from a checkout:

```sh
./setup.sh
```

After bootstrap, update machines with `chezmoi update`.

The previous Ansible setup is archived under `old/ansible/`. Older legacy
Ansible content is archived under `old/legacy/`.
