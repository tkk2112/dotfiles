{
  enable = true;
  userName = "Thomas Kristensen";
  userEmail = "tkristensen@gmail.com";
  aliases = {
    ap    = ''add -p'';
    au    = ''add -u'';
    dfs   = ''diff --stat'';
    dh    = ''diff HEAD'';
    dhs   = ''diff HEAD --stat'';
    ds    = ''diff --staged'';
    dss   = ''diff --staged --stat'';
    co    = ''checkout'';
    ci    = ''commit -v'';
    cia   = ''commit -v --amend'';
    st    = ''status -sb'';
    sm    = ''submodule'';
    ss    = ''show --stat'';
    br    = ''branch -vv'';
    bra   = ''branch -avv'';
    ls    = ''!git --no-pager log --pretty=format:\"%C(green)%h %Creset%s%C(yellow)%d %Creset%C(cyan)<%ae>%Creset\" --graph -20'';
    lsa   = ''log --pretty=format:\"%C(green)%h %Creset%s%C(yellow)%d %Creset%C(cyan)<%ae>%Creset\" --graph -20 --all'';
    lg    = ''log --pretty=format:\"%C(green)%h %C(blue)%ad %Creset%s%C(yellow)%d %Creset%C(cyan)<%an (%ae)>%Creset\" --graph --date=short'';
    lga   = ''log --pretty=format:\"%C(green)%h %C(blue)%ad %Creset%s%C(yellow)%d %Creset%C(cyan)<%an (%ae)>%Creset\" --graph --date=short --all'';
    ff    = ''merge --ff-only @{u}'';
    up    = ''remote update'';
    rup   = ''rebase @{u}'';
    rank  = ''shortlog -s -n --no-merges'';
    desc  = ''describe'';
    track = ''!git branch --set-upstream $(git for-each-ref --format=\"%(refname:short)\" $(git symbolic-ref HEAD))'';
    fixup = ''commit --amend -C HEAD'';
    save  = ''!git add -u && git commit -m \"WIP: $(git show -q --oneline HEAD)\"'';
  };
  extraConfig = {
    branch.autosetuprebase = "remote";
    init.templatedir = "~/.gittemplate";
    github.user = "tkk2112";
    push = {
      default = "upstream";
      followTags = true;
    };
    pull.rebase = true;
    rebase.autoStash = true;
    rerere.enabled = true;
  };
  ignores = [
    ".direnv"
    ".envrc"
  ];
}
