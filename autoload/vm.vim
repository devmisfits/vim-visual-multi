""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Initialize global variables
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let g:VM_live_editing                     = get(g:, 'VM_live_editing', 1)

let g:VM_custom_commands                  = get(g:, 'VM_custom_commands', {})
let g:VM_commands_aliases                 = get(g:, 'VM_commands_aliases', {})
let g:VM_debug                            = get(g:, 'VM_debug', 0)
let g:VM_reselect_first                   = get(g:, 'VM_reselect_first', 0)
let g:VM_case_setting                     = get(g:, 'VM_case_setting', 'smart')
let g:VM_use_first_cursor_in_line         = get(g:, 'VM_use_first_cursor_in_line', 0)
let g:VM_disable_syntax_in_imode          = get(g:, 'VM_disable_syntax_in_imode', 0)
let g:VM_exit_on_1_cursor_left            = get(g:, 'VM_exit_on_1_cursor_left', 0)

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"Reindentation after insert mode

let g:VM_reindent_all_filetypes           = get(g:, 'VM_reindent_all_filetypes', 0)
let g:VM_reindent_filetype                = get(g:, 'VM_reindent_filetype', [])
let g:VM_no_reindent_filetype             = get(g:, 'VM_no_reindent_filetype', ['text', 'markdown'])

call vm#themes#init()
call vm#plugs#buffer()




""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Initialize buffer
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" b:VM_Selection (= s:V) contains Regions, Vars (= s:v = plugin variables),
" function classes (Global, Funcs, Edit, Search, Insert, etc)

" Parameters:
"   empty:  if > 0, the search register will be set to an empty string
"           adding cursors uses 1, starting regex uses 2

fun! vm#init_buffer(empty) abort
    """If already initialized, return current instance."""
    let v:errmsg = ""
    try
        if exists('b:visual_multi') | return s:V | endif

        let b:VM_Selection = {'Vars': {}, 'Regions': [], 'Bytes': {}}
        let b:visual_multi = 1

        let b:VM_Debug           = get(b:, 'VM_Debug', {'lines': []})
        let b:VM_Backup          = {'ticks': [], 'last': 0, 'first': undotree().seq_cur}

        " funcs script must be sourced first
        let s:V            = b:VM_Selection
        let s:v            = s:V.Vars
        let s:V.Funcs      = vm#funcs#init()

        " init plugin variables
        call vm#variables#init()

        if get(g:, 'VM_filesize_limit', 0) && s:V.Funcs.size() > gVM_filesize_limit
            call vm#variables#reset_globals()
            let v:errmsg = 'VM cannot start, buffer too big.'
            return v:errmsg
        endif

        " init search register
        let @/ = a:empty ? '' : @/

        " hooks and compatibility tweaks before applying mappings
        call vm#comp#init()

        " init classes
        let s:V.Maps       = vm#maps#init()
        let s:V.Global     = vm#global#init()
        let s:V.Search     = vm#search#init()
        let s:V.Edit       = vm#edit#init()
        let s:V.Insert     = vm#insert#init()
        let s:V.Block      = vm#block#init()
        let s:V.Case       = vm#special#case#init()

        call s:V.Maps.enable()
        call vm#region#init()
        call vm#commands#init()
        call vm#operators#init()
        call vm#special#commands#init()

        call vm#augroup(0)
        call vm#au_cursor(0)

        " set vim variables
        call vm#variables#set()

        if !empty(g:VM_highlight_matches)
            if !has_key(g:Vm, 'Search')
                call vm#themes#init()
            else
                call vm#themes#hi()
            endif
            hi clear Search
            exe g:Vm.Search
        endif

        if &hlsearch && !v:hlsearch && a:empty != 2
            let s:v.oldhls = 1
            if !g:Vm.selecting
                call feedkeys("\<Plug>(VM-Noh)")
            endif
        else
            let s:v.oldhls = 0
        endif

        call s:V.Funcs.set_statusline(0)

        " backup sync settings for the buffer
        if !exists('b:VM_sync_minlines')
            let b:VM_sync_minlines = s:V.Funcs.sync_minlines()
        endif

        let g:Vm.is_active = 1
        return s:V
    catch
        let v:errmsg = 'VM cannot start, unhandled exception.'
        call vm#variables#reset_globals()
        return v:errmsg
    endtry
endfun


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Reset
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

fun! vm#reset(...)
    call vm#variables#reset()

    if s:v.oldhls
        call feedkeys("\<Plug>(VM-Noh)")
    endif

    call vm#commands#regex_reset()

    let s:v.clear_vm_matches = 1
    call s:V.Global.remove_highlight()
    call s:V.Global.backup_last_regions()

    call s:V.Funcs.restore_regs()
    call s:V.Maps.disable(1)
    silent! call s:V.Insert.auto_end()

    call vm#maps#reset()
    call vm#comp#reset()
    call vm#augroup(1)
    call vm#au_cursor(1)

    " reenable folding, but keep winline and open current fold
    if exists('s:v.oldfold')
        call s:V.Funcs.Scroll.get(1)
        normal! zizv
        call s:V.Funcs.Scroll.restore()
    endif

    if !empty(g:VM_highlight_matches)
        hi clear Search
        exe g:Vm.search_hi
    endif

    if g:Vm.oldupdate && &updatetime != g:Vm.oldupdate
        let &updatetime = g:Vm.oldupdate
    endif

    call vm#comp#exit()

    "exiting manually
    if !get(g:, 'VM_silent_exit', 0) && !a:0
        call s:V.Funcs.msg('Exited Visual-Multi.')
    endif

    call vm#variables#reset_globals()
    call vm#special#commands#unset()
    unlet b:visual_multi
    call garbagecollect()
endfun

"------------------------------------------------------------------------------

fun! vm#clearmatches() abort
    for m in getmatches()
        if m.group == 'VM_Extend' || m.group == 'MultiCursor'
            call matchdelete(m.id)
        endif
    endfor
endfun


""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Autocommands
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

fun! vm#augroup(end) abort
    if a:end
        autocmd! VM_global
        augroup! VM_global
        return
    endif

    augroup VM_global
        au!
        au BufLeave     * call s:buffer_leave()
        au BufEnter     * call s:buffer_enter()

        if exists("##TextYankPost")
            au TextYankPost * call s:set_reg()
            au TextYankPost * call vm#operators#after_yank()
        else
            au CursorMoved  * call s:set_reg()
            au CursorMoved  * call vm#operators#after_yank()
            au CursorHold   * call vm#operators#after_yank()
        endif
    augroup END
endfun

fun! vm#au_cursor(end) abort
    if a:end
        autocmd! VM_cursormoved
        augroup! VM_cursormoved
        return
    endif

    augroup VM_cursormoved
        au!
        au CursorMoved  * call s:cursor_moved()
        au CursorMoved  * call s:V.Funcs.set_statusline(2)
        au CursorHold   * call s:V.Funcs.set_statusline(1)
    augroup END
endfun

fun! s:cursor_moved() abort
    if s:v.block_mode
        if !s:v.block[3]
            call s:V.Block.stop()
        else
            let s:v.block[3] = 0
        endif

    elseif !s:v.eco
        " if currently on a region, set the index to this region
        " so that it's possible to select next/previous from it
        let r = s:V.Global.region_at_pos()
        if !empty(r) | let s:v.index = r.index | endif
    endif
endfun

fun! s:buffer_leave() abort
    if !empty(get(b:, 'VM_Selection', {})) && !b:VM_Selection.Vars.insert
        call vm#reset(1)
    endif
endfun

fun! s:buffer_enter() abort
    if empty(get(b:, 'VM_Selection', {}))
        let b:VM_Selection = {}
    endif
endfun

fun! s:set_reg() abort
    "Replace old default register if yanking in VM outside a region or cursor
    if s:v.yanked
        let s:v.yanked = 0
        let g:Vm.registers['"'] = []
        let s:v.oldreg = s:V.Funcs.get_reg(v:register)
    endif
endfun

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"python section
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

if !has('python3')
    let g:VM_use_python = 0
    finish
endif

let g:VM_use_python = get(g:, 'VM_use_python', !has('nvim'))
if !g:VM_use_python | finish | endif

let s:root_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

python3 << EOF
import sys
from os.path import normpath, join
import vim
root_dir = vim.eval('s:root_dir')
python_root_dir = normpath(join(root_dir, '..', 'python'))
sys.path.insert(0, python_root_dir)
import vm
EOF
" vim: et ts=4 sw=4 sts=4 :
