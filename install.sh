#!/bin/bash

function cmd_exists {
    command -v $1 >/dev/null 2>&1
}

pushd $(dirname $0) > /dev/null
repo=$(pwd)
popd > /dev/null
temp=$(mktemp -d)

run_sudo=
if [ "$EUID" -ne 0 ]; then
    run_sudo=sudo
fi

$run_sudo apt-get update


###### pip ######
if ! cmd_exists pip; then
    $run_sudo apt-get install -y python-pip python-dev
    $run_sudo apt-get install -y python3-pip python3-dev
fi
$run_sudo pip install --upgrade pip
$run_sudo pip3 install --upgrade pip


###### fzf ######
if ! cmd_exists fzf; then
    cd $temp
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all --key-bindings --completion
    cd $repo
fi


###### silversearcher-ag ######
if ! cmd_exists ag; then
    $run_sudo apt-get install -y silversearcher-ag
fi


###### tmux ######
if ! cmd_exists tmux; then
    $run_sudo apt-get install -y cmake
    $run_sudo apt-get install -y tmux
fi
rm -rf ~/.tmux.conf && ln -s $repo/.tmux.conf ~/.tmux.conf
rm -rf ~/.tmux
mkdir -p ~/.tmux/plugins
cd ~/.tmux/plugins
git clone --depth 1 https://github.com/tmux-plugins/tpm
chmod +x tpm/bin/*
tpm/bin/install_plugins
cd tmux-mem-cpu-load
cmake .
make


###### neovim ######
if ! cmd_exists nvim; then
    $run_sudo apt-get install -y neovim

    $run_sudo update-alternatives --install /usr/bin/vi vi /usr/bin/nvim 60
    $run_sudo update-alternatives --set vi /usr/bin/nvim
    $run_sudo update-alternatives --install /usr/bin/vim vim /usr/bin/nvim 60
    $run_sudo update-alternatives --set vim /usr/bin/nvim
    $run_sudo update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60
    $run_sudo update-alternatives --set editor /usr/bin/nvim

    # plugins
    mkdir ~/.vim-plugged
    cd ~/.vim-plugged
    for r in $(cat $repo/nvim/init.vim | grep "Plug '" | awk '{print $2}' | sed s,\',,g); do git clone https://github.com/$r; done

fi
$run_sudo pip install --upgrade neovim
$run_sudo pip3 install --upgrade neovim
mkdir ~/.config
rm -rf ~/.config/nvim && ln -s $repo/nvim ~/.config/nvim

###### pygmentize ######
if ! cmd_exists pygmentize; then
    $run_sudo apt-get install -y python-pygments
fi
rm -rf ~/.lessfilter && ln -s $repo/.lessfilter ~/.lessfilter

###### spacemacs ######
git clone https://github.com/syl20bnr/spacemacs ~/.emacs.d
sudo apt install -y emacs
ln -s $repo/.spacemacs ~/.spacemacs

###### misc ######
mkdir ~/bin
rm -rf ~/bin/tmux_completion.sh && ln -s $repo/tmux_completion.sh ~/bin/tmux_completion.sh
cat ~/.bashrc | grep PATH= | grep "~/bin" || echo "export PATH=\${PATH}:~/bin" >> ~/.bashrc
rm -rf ~/.bashrc_extras && ln -s $repo/.bashrc_extras ~/.bashrc_extras
cat ~/.bashrc | grep bashrc_extras || echo "source ~/.bashrc_extras" >> ~/.bashrc

rm -rf $temp

if [ -f ~/.gitconfig ]; then
    exit 0
fi

cat<<EOB > ~/.gitconfig
[alias]
        co = checkout
        br = branch
        ci = commit
        st = status
[pull]
        rebase = true
[rebase]
        autoStash = true
EOB
