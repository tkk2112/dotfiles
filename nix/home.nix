{ config, pkgs, ... }:
{
  imports = [
    ./home/tmux.nix
    ./home/vim.nix
  ];

  home.packages = with pkgs; [
    (aspellWithDicts (dicts: with dicts; [
      en
      en-computers
      nb
    ]))
    jq
    ncdu
    silversearch-ag
    tree
  ];

  programs = {
    # Let Home Manager install and manage itself.
    home-manager.enable = true;

    bat.enable = true;
    direnv = import ./home/direnv.nix;
    fzf.enable = true;
    git = import ./home/git.nix;
    htop.enable = true;
    zsh.enable = true;
  };
}
