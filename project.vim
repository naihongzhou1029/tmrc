args! project.vim
argadd **/*.md

" Open terminal at bottom-right and run agent (Vim 8.1+ / Neovim with +terminal).
" Passing the command to :terminal runs it as soon as the terminal is ready;
" avoids term_send (Vim-only) and timer timing issues.
botright vertical terminal agent

" \t: open specs/test.md with Quick Look via :!
function! s:OpenTestPreview() abort
  let path = findfile('specs/test.md', '.;')
  if empty(path)
    let path = getcwd() . '/specs/test.md'
  endif
  let path = fnamemodify(path, ':p')
  if !filereadable(path)
    echomsg 'Not found: ' . path
    return
  endif
  execute '!qlmanage -p ' . fnameescape(path)
endfunction
nnoremap <leader>t :call <SID>OpenTestPreview()<CR>
