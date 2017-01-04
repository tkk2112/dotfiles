" Basics {
    set nocompatible " explicitly get out of vi-compatible mode

    " vim-plug {
        call plug#begin('~/.vim-plugged')

        Plug 'junegunn/fzf.vim'
        Plug 'rbgrouleff/bclose.vim'
        Plug 'fugalh/desert.vim'
        Plug 'sjl/gundo.vim'
        Plug 'haya14busa/incsearch.vim'
        Plug 'cdmedia/itg_flat_vim'
        Plug 'scrooloose/syntastic'
        Plug 'marijnh/tern_for_vim'
        Plug 'bling/vim-airline'
        Plug 'Lokaltog/vim-distinguished'
        Plug 'idanarye/vim-dutyl'
        Plug 'Lokaltog/vim-easymotion'
        Plug 'derekwyatt/vim-fswitch'
        Plug 'tpope/vim-fugitive'
        Plug 'nathanaelkane/vim-indent-guides'
        Plug 'jelera/vim-javascript-syntax'
        Plug 'tmux-plugins/vim-tmux'
        Plug 'tmux-plugins/vim-tmux-focus-events'
        Plug 'idanarye/vim-vebugger'
        Plug 'wellsjo/wells-colorscheme.vim'
        Plug 'Valloric/YouCompleteMe', { 'do': './install.py --clang-completer --system-libclang' }

        call plug#end()
    " }

    " reload .vimrc on write
    au! BufWritePost ~/.vimrc                 so ~/.vimrc
    au! BufWritePost $HOME/.vim/vimpython.py  pynfile $HOME/.vim/vimpython.py

    set t_Co=256 " force 256 colors
    set background=dark " we plan to use a dark background
    colorscheme mushroom

    let mapleader="," " set leader to ,
    set cpoptions=aABceFsmq
    "             |||||||||
    "             ||||||||+-- When joining lines, leave the cursor between joined lines
    "             |||||||+-- When a new match is created (showmatch) pause for .5
    "             ||||||+-- Set buffer options when entering the buffer
    "             |||||+-- :write command updates current file name
    "             ||||+-- Automatically add <CR> to the last line when using :@r
    "             |||+-- Searching continues at the end of the match at the cursor position
    "             ||+-- A backslash has no special meaning in mappings
    "             |+-- :write updates alternative file name
    "             +-- :read updates alternative file name
    syntax on " syntax highlighting on
" }

" General {
    filetype plugin indent on " load filetype plugins/indent settings
    set binary " enable binary support
    set autoread " auto reload
    set backspace=indent,eol,start " make backspace a more flexible
    set backup " make backup files
    set backupdir=/tmp " where to put backup files
    set clipboard+=unnamed " share windows clipboard
    set directory=/tmp " directory to place swap files in
    set fileformats=unix,mac,dos " support all three, in this order
    set hidden " you can change buffers without saving
    set iskeyword+=_,$,@,%,# " none of these are word dividers
    set mouse=a " use mouse everywhere
    set noerrorbells " don't make noise
    set virtualedit=onemore " allow for cursor beyond last character
    set history=1000 " Store a ton of history
    set noswapfile " Turns off swap

    set whichwrap=b,s,h,l,<,>,~,[,] " everything wraps
    "             | | | | | | | | |
    "             | | | | | | | | +-- "]" Insert and Replace
    "             | | | | | | | +-- "[" Insert and Replace
    "             | | | | | | +-- "~" Normal
    "             | | | | | +-- <Right> Normal and Visual
    "             | | | | +-- <Left> Normal and Visual
    "             | | | +-- "l" Normal and Visual (not recommended)
    "             | | +-- "h" Normal and Visual (not recommended)
    "             | +-- <Space> Normal and Visual
    "             +-- <BS> Normal and Visual
    set wildmenu " turn on command line completion wild style
    " ignore these list file extensions
    set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.dll,*.o,*.obj,*.bak,*.exe,*.pyc,*.jpg,*.gif,*.png
    set wildmode=list:longest " turn on wild mode huge list
" }

" Vim UI {
    set incsearch " BUT do highlight as you type you search phrase
    set laststatus=2 " always show the status line
    set lazyredraw " do not redraw while running macros
    set linespace=0 " don't insert any extra pixel lines betweens rows
    set list " we do what to show tabs, to ensure we get them out of my files
    set listchars=tab:>-,trail:- " show tabs and trailing
    set matchtime=5 " how many tenths of a second to blink matching brackets for
    set nohlsearch " do not highlight searched for phrases
    set nostartofline " leave my cursor where it was
    set novisualbell " don't blink
    set number " turn on line numbers
    set numberwidth=5 " We are good up to 99999 lines
    set report=0 " tell us when anything is changed via :...
    set ruler " Always show current positions along the bottom
    set scrolloff=10 " Keep 10 lines (top/bottom) for scope
    set shortmess=aOstT " shortens messages to avoid 'press a key' prompt
    set showcmd " show the command being typed
    set showmatch " show matching brackets
    set sidescrolloff=10 " Keep 5 lines at the size
    set statusline=%F%m%r%h%w[%L][%{&ff}]%y[%p%%][%04l,%04v]
    "              | | | | |  |   |      |  |     |    |
    "              | | | | |  |   |      |  |     |    + current column
    "              | | | | |  |   |      |  |     +-- current line
    "              | | | | |  |   |      |  +-- current % into file
    "              | | | | |  |   |      +-- current syntax in square brackets
    "              | | | | |  |   +-- current fileformat
    "              | | | | |  +-- number of lines
    "              | | | | +-- preview flag in square brackets
    "              | | | +-- help flag in square brackets
    "              | | +-- readonly flag in square brackets
    "              | +-- rodified flag in square brackets
    "              +-- full path to file in the buffer

    " open split panes below and to the right
    set splitbelow
    set splitright
    set cursorline " highlight the current line horisontaly
" }

" Text Formatting/Layout {
    set completeopt=longest,menuone " use a pop up menu for completions
    set formatoptions=rq " Automatically insert comment leader on return, and let gq format comments
    set ignorecase " case insensitive by default
    set infercase " case inferred by default
    set nowrap " do not wrap line
    set shiftround " when at 3 spaces, and I hit > ... go to 4, not 5
    set smartcase " if there are caps, go case-sensitive
    set tabstop=8 " real tabs should be 8, and they will show with set list on
    set shiftwidth=4 " auto-indent amount when using cindent, >>, << and stuff like that
    set softtabstop=4 " when hitting tab or backspace, how many spaces should a tab be (see expandtab)
    set expandtab " no real tabs please!
    " allow toggling between local and default mode
    function! TabToggle()
      if &expandtab
        set shiftwidth=8
        set softtabstop=0
        set noexpandtab
      else
        set shiftwidth=4
        set softtabstop=4
        set expandtab
      endif
    endfunction

    " set textwidth=120 " set textwidth to 120
    " set colorcolumn=+1 " set width of color column
    au! BufWritePre <buffer> :%s/\s\+$//e " delete trailing whitespace on save
" }

" Folding {
    set foldenable " Turn on folding
    set foldmarker={,} " Fold C style code (only use this as default if you use a high foldlevel)
    set foldmethod=marker " Fold on the marker
    set foldlevel=100 " Don't autofold anything (but I can still fold manually)
    set foldopen=block,hor,mark,percent,quickfix,tag " what movements open folds
    function! SimpleFoldText() " {
        return getline(v:foldstart).' '
    endfunction " }
    set foldtext=SimpleFoldText() " Custom fold text function (cleaner than default)
" }


" Feature based Settings {

    if has("nvim")
        let $NVIM_TUI_ENABLE_CURSOR_SHAPE=1
    endif

    if has("gui_running")
        colorscheme oceandeep
        set cursorline " highlight current line
        set columns=140
        set lines=70

        if has("gui_gtk2")
            set guifont=Monospace\ 9
            "set guifont=ProFont\ 8
        else
           set guifont=Monaco:h10
        endif
        set guioptions=ce
        "              ||
        "              |+-- use simple dialogs rather than pop-ups
        "              +  use GUI tabs, not console style tabs
        set mousehide " hide the mouse cursor when typing
    endif
" }

" Custom coloring {
    hi PmenuSel cterm=bold ctermfg=16 ctermbg=214 guifg=#ffffff guibg=magenta
    hi Pmenu ctermfg=251 ctermbg=241 guifg=#2d2d2d guibg=#333333
" }

" Syntax highlight {
    au! BufRead,BufNewFile *.qml        setfiletype qml
    au! BufRead,BufNewFile *.hla        setfiletype hla
    au! BufRead,BufNewFile *.asm        setfiletype asmx86
    au! BufRead,BufNewFile *.vala       setfiletype vala
    au! BufRead,BufNewFile *.vapi       setfiletype vala
" }

" Plugin Settings {
    " FSwitch
    au! BufEnter *.cpp let b:fswitchdst = 'hpp,h' | let b:fswitchlocs = '../inc'

    " Syntastic
    set statusline+=%#warningmsg#
    set statusline+=%{SyntasticStatuslineFlag()}
    set statusline+=%*
    let g:syntastic_always_populate_loc_list = 1
    let g:syntastic_auto_loc_list = 1
    let g:syntastic_check_on_open = 1
    let g:syntastic_check_on_wq = 0
    let g:syntastic_python_python_exec = '/usr/bin/python3'
    let g:syntastic_python_checkers = ['python']

    " vim-javascript
    au! FileType javascript call JavaScriptFold()
    let regexengine = 1

    let g:ycm_global_ycm_extra_conf = "~/.config/nvim/.ycm_extra_conf.py"

    " fzf.vim {
        " Mapping selecting mappings
        nmap <leader><tab> <plug>(fzf-maps-n)
        map <leader><tab> <plug>(fzf-maps-x)
        omap <leader><tab> <plug>(fzf-maps-o)

        " Insert mode completion
        imap <c-x><c-k> <plug>(fzf-complete-word)
        imap <c-x><c-f> <plug>(fzf-complete-path)
        imap <c-x><c-j> <plug>(fzf-complete-file-ag)
        imap <c-x><c-l> <plug>(fzf-complete-line)
    " }
" }

" Mappings {
    " enter selects menu item if autocomplete menu is open
    inoremap <expr> <CR> pumvisible() ? "\<C-y>" : "\<CR>"

    " For when you forget to sudo.. Really Write the file.
    cnoremap w!! w !sudo tee % >/dev/null

    " esc is hard to hit on some laptops, lets also enable f1
    inoremap <F1> <ESC>
    nnoremap <F1> <ESC>
    vnoremap <F1> <ESC>

    " space / shift-space scroll in normal mode
    noremap <S-space> <C-b>
    noremap <space> <C-f>

    " Making it so ; works like : for commands. Saves typing and eliminates :W style typos due to lazy holding shift.
    nnoremap ; :

    " Yank from the cursor to the end of the line, to be consistent with C and D.
    nnoremap Y y$

    " Stupid shift key fixes
    cnoremap WQ wq
    cnoremap Wq wq

    " switch between tabs/spaces
    noremap <F9> mz:execute TabToggle()<CR>'z

    " go to header/source
    noremap <f4> :FSHere<cr>

    " undo history
    noremap <f6> :GundoToggle<CR>

    " switch 0 and <Home>
    function! ExtendedHome()
        let column = col('.')
        normal! ^
        if column == col('.')
            normal! 0
        endif
    endfunction
    noremap <silent> <Home> :call ExtendedHome()<CR>
    inoremap <silent> <Home> <C-O>:call ExtendedHome()<CR>

    " Q is stupid
    map Q <Nop>

    " system clipboard copy & paste
    vnoremap <C-c> "*y
    set pastetoggle=<F10>
    inoremap <C-v> <F10><C-r>*<F10>

    " buffer tree
    noremap <f3> :Buffers<CR>

    " remap auto-complete
    if has("gui_running")
        inoremap <C-Space> <C-n>
    else
        if has("unix")
            inoremap <Nul> <C-n>
        endif
    endif

    " leader maps
    nnoremap <Leader>e :e <C-R>=expand('%:p:h') . '/'<CR>
    nnoremap <Leader>E :e <C-R>=expand('%:p')<CR>

    " incsearch
    "map /  <Plug>(incsearch-forward)
    "map ?  <Plug>(incsearch-backward)
    "map g/ <Plug>(incsearch-stay)

    " easymotion
    let g:EasyMotion_leader_key='<C-Leader>'
    nmap <Leader><Leader> <Plug>(easymotion-overwin-f)
    xmap <Leader><Leader> <Plug>(easymotion-bd-f)
    omap <Leader><Leader> <Plug>(easymotion-bd-f)

    nnoremap <Leader>r :w<CR>:!./<C-r>%<CR>

    map <C-k> :FZF<CR>

    " Close buffer
    nnoremap <silent> <Leader>q :Bdelete<CR>
    nnoremap <silent> <Leader>bd :Bdelete!<CR>
" }

" Misc {
    " XML folding
    let g:xml_syntax_folding=1
    au FileType xml setlocal foldmethod=syntax

    if executable('ag')
        " Use Ag over Grep
        set grepprg=ag\ --nogroup\ --nocolor
    endif

    " live search/replace
    if has("nvim")
        set inccommand=nosplit
    endif

" }
