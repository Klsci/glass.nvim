" glass.nvim - Universal transparency plugin with glass pane effects
" Maintainer: Klsci
" License: MIT

if exists('g:loaded_glass') | finish | endif
let g:loaded_glass = 1

" Auto-setup with default config if not already configured
if !exists('g:glass_configured')
  lua require('glass').setup()
  let g:glass_configured = 1
endif
