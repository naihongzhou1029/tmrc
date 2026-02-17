args! project.vim
argadd **/*.md
argadd devops.sh

" Open terminal at bottom-right and run agent (Vim 8.1+ / Neovim with +terminal).
" Passing the command to :terminal runs it as soon as the terminal is ready;
" avoids term_send (Vim-only) and timer timing issues.
botright vertical terminal agent
