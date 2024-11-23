if exists('g:loaded_fzf_vim')
  finish
endif
let g:loaded_fzf_vim = 1

let s:base_dir = expand('<sfile>:h:h')
let s:term_marker = ";#FZF"

function! s:shellesc_cmd(arg)
  let e = '"'
  let slashes = 0
  for c in split(a:arg, '\zs')
    if c ==# '\'
      let slashes += 1
    elseif c ==# '"'
      let e .= repeat('\', slashes + 1)
      let slashes = 0
    else
      let slashes = 0
    endif
    let e .= c
  endfor
  let e .= repeat('\', slashes) .'"'
  return substitute(substitute(e, '[&|<>()^!"]', '^&', 'g'), '%', '%%', 'g')
endfunction

function! s:fzf_expand(fmt)
  return expand(a:fmt, 1)
endfunction

let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:fzf_go = s:base_dir.'/bin/fzf'

function! s:default_layout()
  return has('popupwin')
        \ ? { 'window' : { 'width': 0.9, 'height': 0.6 } }
        \ : { 'down': '~40%' }
endfunction

let s:versions = {}
function s:get_version(bin)
  if has_key(s:versions, a:bin)
    return s:versions[a:bin]
  end
  let command = shellescape(a:bin) . ' --version --no-height'
  let output = systemlist(command)
  if v:shell_error || empty(output)
    return ''
  endif
  let ver = matchstr(output[-1], '[0-9.]\+')
  let s:versions[a:bin] = ver
  return ver
endfunction

function! s:compare_versions(a, b)
  let a = split(a:a, '\.')
  let b = split(a:b, '\.')
  for idx in range(0, max([len(a), len(b)]) - 1)
    let v1 = str2nr(get(a, idx, 0))
    let v2 = str2nr(get(b, idx, 0))
    if     v1 < v2 | return -1
    elseif v1 > v2 | return 1
    endif
  endfor
  return 0
endfunction

function! s:compare_binary_versions(a, b)
  return s:compare_versions(s:get_version(a:a), s:get_version(a:b))
endfunction

let s:min_version = '0.53.0'
let s:checked = {}
function! fzf#exec(...)
  if !exists('s:exec')
    let binaries = []
    if executable('fzf')
      call add(binaries, 'fzf')
    endif
    if executable(s:fzf_go)
      call add(binaries, s:fzf_go)
    endif

    if empty(binaries)
      redraw
      throw 'fzf executable not found'
    elseif len(binaries) > 1
      call sort(binaries, 's:compare_binary_versions')
    endif

    let s:exec = binaries[-1]
  endif

  let min_version = s:min_version
  if a:0 && s:compare_versions(a:1, min_version) > 0
    let min_version = a:1
  endif
  if !has_key(s:checked, min_version)
    let fzf_version = s:get_version(s:exec)
    if empty(fzf_version)
      let message = printf('Failed to run "%s --version"', s:exec)
      unlet s:exec
      throw message
    end

    if s:compare_versions(fzf_version, min_version) >= 0
      let s:checked[min_version] = 1
      return s:exec
    elseif a:0 < 2 && input(printf('You need fzf %s or above. Found: %s. Download binary? (y/n) ', min_version, fzf_version)) =~? '^y'
      let s:versions = {}
      unlet s:exec
      redraw
      return fzf#exec(min_version, 1)
    else
      throw printf('You need to upgrade fzf (required: %s or above)', min_version)
    endif
  endif

  return s:exec
endfunction

function! s:has_any(dict, keys)
  for key in a:keys
    if has_key(a:dict, key)
      return 1
    endif
  endfor
  return 0
endfunction

function! s:open(cmd, target)
  if stridx('edit', a:cmd) == 0 && fnamemodify(a:target, ':p') ==# s:fzf_expand('%:p')
    return
  endif
  execute a:cmd fnameescape(a:target)
endfunction

function! s:common_sink(action, lines) abort
  if len(a:lines) < 2
    return
  endif
  let key = remove(a:lines, 0)
  let Cmd = get(a:action, key, 'e')
  if type(Cmd) == type(function('call'))
    return Cmd(a:lines)
  endif
  if len(a:lines) > 1
    augroup fzf_swap
      autocmd SwapExists * let v:swapchoice='o'
            \| call fzf#utils#Warn('fzf: E325: swap file exists: '.s:fzf_expand('<afile>'))
    augroup END
  endif
  try
    let empty = empty(s:fzf_expand('%')) && line('$') == 1 && empty(getline(1)) && !&modified
    " Preserve the current working directory in case it's changed during
    " the execution (e.g. `set autochdir` or `autocmd BufEnter * lcd ...`)
    let cwd = exists('w:fzf_pushd') ? w:fzf_pushd.dir : expand('%:p:h')
    for item in a:lines
      if has('win32unix') && item !~ '/'
        let item = substitute(item, '\', '/', 'g')
      end
      if item[0] != '~' && item !~ '^/'
        let sep = '/'
        let item = join([cwd, item], cwd[len(cwd)-1] == sep ? '' : sep)
      endif
      if empty
        execute 'e' fnameescape(item)
        let empty = 0
      else
        call s:open(Cmd, item)
      endif
      if isdirectory(item)
        doautocmd BufEnter
      endif
    endfor
  catch /^Vim:Interrupt$/
  finally
    silent! autocmd! fzf_swap
  endtry
endfunction

function! s:get_color(attr, ...)
  " Force 24 bit colors: g:fzf_force_termguicolors (temporary workaround for https://github.com/junegunn/fzf.vim/issues/1152)
  let gui = get(g:, 'fzf_force_termguicolors', 0) 
  let fam = gui ? 'gui' : 'cterm'
  let pat = gui ? '^#[a-f0-9]\+' : '^[0-9]\+$'
  for group in a:000
    let code = synIDattr(synIDtrans(hlID(group)), a:attr, fam)
    if code =~? pat
      return code
    endif
  endfor
  return ''
endfunction

function! s:defaults()
  let rules = copy(get(g:, 'fzf_colors', {}))
  let colors = join(map(items(filter(map(rules, 'call("s:get_color", v:val)'), '!empty(v:val)')), 'join(v:val, ":")'), ',')
  return empty(colors) ? '' : shellescape('--color='.colors)
endfunction

function! s:validate_layout(layout)
  for key in keys(a:layout)
    if index(s:layout_keys, key) < 0
      throw printf('Invalid entry in g:fzf_layout: %s (allowed: %s)%s',
            \ key, join(s:layout_keys, ', '), key == 'options' ? '. Use $FZF_DEFAULT_OPTS.' : '')
    endif
  endfor
  return a:layout
endfunction

function! s:evaluate_opts(options)
  return type(a:options) == type([]) ?
        \ join(map(copy(a:options), 'shellescape(v:val)')) : a:options
endfunction

" [name string,] [opts dict,] [fullscreen boolean]
function! fzf#wrap(...)
  let args = ['', {}, 0]
  let expects = map(copy(args), 'type(v:val)')
  let tidx = 0
  for arg in copy(a:000)
    let tidx = index(expects, type(arg) == 6 ? type(0) : type(arg), tidx)
    if tidx < 0
      throw 'Invalid arguments (expected: [name string] [opts dict] [fullscreen boolean])'
    endif
    let args[tidx] = arg
    let tidx += 1
    unlet arg
  endfor
  let [name, opts, bang] = args

  if len(name)
    let opts.name = name
  end

  " Layout: g:fzf_layout (and deprecated g:fzf_height)
  if bang
    for key in s:layout_keys
      if has_key(opts, key)
        call remove(opts, key)
      endif
    endfor
  elseif !s:has_any(opts, s:layout_keys)
    if !exists('g:fzf_layout') && exists('g:fzf_height')
      let opts.down = g:fzf_height
    else
      let opts = extend(opts, s:validate_layout(get(g:, 'fzf_layout', s:default_layout())))
    endif
  endif

  " Colors: g:fzf_colors
  let opts.options = s:defaults() .' '. s:evaluate_opts(get(opts, 'options', ''))

  " History: g:fzf_history_dir
  if len(name) && len(get(g:, 'fzf_history_dir', ''))
    let dir = s:fzf_expand(g:fzf_history_dir)
    if !isdirectory(dir)
      call mkdir(dir, 'p')
    endif
    let history = shellescape(dir.'/'.name)
    let opts.options = join(['--history', history, opts.options])
  endif

  " Action: g:fzf_action
  if !s:has_any(opts, ['sink', 'sinklist', 'sink*'])
    let opts._action = get(g:, 'fzf_action', s:default_action)
    let opts.options .= ' --expect='.join(keys(opts._action), ',')
    function! opts.sinklist(lines) abort
      return s:common_sink(self._action, a:lines)
    endfunction
    let opts['sink*'] = opts.sinklist " For backward compatibility
  endif

  return opts
endfunction

function! s:writefile(...)
  if call('writefile', a:000) == -1
    throw 'Failed to write temporary file. Check if you can write to the path tempname() returns.'
  endif
endfunction

function! s:extract_option(opts, name)
  let opt = ''
  let expect = 0
  " There are a few cases where this function doesn't work as expected.
  " Let's just assume such cases are extremely unlikely in real world.
  "   e.g. --query --border
  for word in split(a:opts)
    if expect && word !~ '^"\=-'
      let opt = opt . ' ' . word
      let expect = 0
    elseif word == '--no-'.a:name
      let opt = ''
    elseif word =~ '^--'.a:name.'='
      let opt = word
    elseif word =~ '^--'.a:name.'$'
      let opt = word
      let expect = 1
    elseif expect
      let expect = 0
    endif
  endfor
  return opt
endfunction

let s:need_cmd_window = has('win32unix') && $TERM_PROGRAM ==# 'mintty' && s:compare_versions($TERM_PROGRAM_VERSION, '3.4.5') < 0 && !executable('winpty')

function! fzf#run(...) abort
  try
    let dict   = exists('a:1') ? copy(a:1) : {}
    let temps  = { 'result': tempname() }
    let optstr = s:evaluate_opts(get(dict, 'options', ''))
    try
      let fzf_exec = shellescape(fzf#exec())
    catch
      throw v:exception
    endtry

    if !s:present(dict, 'dir')
      let dict.dir = getcwd()
    endif
    if has('win32unix') && s:present(dict, 'dir')
      let dict.dir = fnamemodify(dict.dir, ':p')
    endif

    if has_key(dict, 'source')
      let source = dict.source
      let type = type(source)
      if type == 1
        let prefix = '('.source.')|'
      elseif type == 3
        let temps.input = tempname()
        call s:writefile(source, temps.input)
        let prefix = 'command cat '.shellescape(temps.input).'|'
      else
        throw 'Invalid source type'
      endif
    else
      let prefix = ''
    endif

    let use_height = has_key(dict, 'down') && !has('gui_running') &&
          \ !(s:present(dict, 'up', 'left', 'right', 'window')) &&
          \ executable('tput') && filereadable('/dev/tty')
    let use_term = has('terminal')
          \ && !s:need_cmd_window
          \ && (has('gui_running') || s:present(dict, 'down', 'up', 'left', 'right', 'window'))
    if use_term
      let optstr .= ' --no-height --no-tmux'
    elseif use_height
      let height = s:calc_size(&lines, dict.down, dict)
      let optstr .= ' --no-tmux --height='.height
    endif
    " Respect --border option given in $FZF_DEFAULT_OPTS and 'options'
    let optstr = join([s:border_opt(get(dict, 'window', 0)), s:extract_option($FZF_DEFAULT_OPTS, 'border'), optstr])
    let command = prefix.fzf_exec.' '.optstr.' > '.temps.result

    if use_term
      return s:execute_term(dict, command, temps)
    endif

    let lines = s:execute(dict, command, use_height, temps)
    call s:callback(dict, lines)
    return lines
  endtry
endfunction

function! s:present(dict, ...)
  for key in a:000
    if !empty(get(a:dict, key, ''))
      return 1
    endif
  endfor
  return 0
endfunction

function! s:splittable(dict)
  return s:present(a:dict, 'up', 'down') && &lines > 15 ||
        \ s:present(a:dict, 'left', 'right') && &columns > 40
endfunction

function! s:pushd(dict)
  if s:present(a:dict, 'dir')
    let cwd = getcwd()
    let w:fzf_pushd = {
          \   'command': haslocaldir() ? 'lcd' : (exists(':tcd') && haslocaldir(-1) ? 'tcd' : 'cd'),
          \   'origin': cwd,
          \   'bufname': bufname('')
          \ }
    execute 'lcd' fnameescape(a:dict.dir)
    let cwd = getcwd()
    let w:fzf_pushd.dir = cwd
    let a:dict.pushd = w:fzf_pushd
    return cwd
  endif
  return ''
endfunction

augroup fzf_popd
  autocmd!
  autocmd WinEnter * call s:dopopd()
augroup END

function! s:dopopd()
  if !exists('w:fzf_pushd')
    return
  endif

  " FIXME: We temporarily change the working directory to 'dir' entry
  " of options dictionary (set to the current working directory if not given)
  " before running fzf.
  "
  " e.g. call fzf#run({'dir': '/tmp', 'source': 'ls', 'sink': 'e'})
  "
  " After processing the sink function, we have to restore the current working
  " directory. But doing so may not be desirable if the function changed the
  " working directory on purpose.
  "
  " So how can we tell if we should do it or not? A simple heuristic we use
  " here is that we change directory only if the current working directory
  " matches 'dir' entry. However, it is possible that the sink function did
  " change the directory to 'dir'. In that case, the user will have an
  " unexpected result.
  if getcwd() ==# w:fzf_pushd.dir && (!&autochdir || w:fzf_pushd.bufname ==# bufname(''))
    execute w:fzf_pushd.command fnameescape(w:fzf_pushd.origin)
  endif
  unlet! w:fzf_pushd
endfunction

function! s:exit_handler(dict, code, command, ...)
  if has_key(a:dict, 'exit')
    call a:dict.exit(a:code)
  endif
  if a:code == 2
    call fzf#utils#Error('Error running ' . a:command)
    if !empty(a:000)
      sleep
    endif
  endif
  return a:code
endfunction

function! s:execute(dict, command, use_height, temps) abort
  call s:pushd(a:dict)
  if has('unix') && !a:use_height
    silent! !clear 2> /dev/null
  endif
  let escaped = (a:use_height) ? a:command : escape(substitute(a:command, '\n', '\\n', 'g'), '%#!')
  if has('gui_running')
    let Launcher = get(a:dict, 'launcher', get(g:, 'Fzf_launcher', get(g:, 'fzf_launcher', s:launcher)))
    let fmt = type(Launcher) == 2 ? call(Launcher, []) : Launcher
    if has('unix')
      let escaped = "'".substitute(escaped, "'", "'\"'\"'", 'g')."'"
    endif
    let command = printf(fmt, escaped)
  else
    let command = escaped
  endif
  if s:need_cmd_window
    let shellscript = tempname()
    call s:writefile([command], shellscript)
    let command = 'start //WAIT sh -c '.shellscript
    let a:temps.shellscript = shellscript
  endif
  if a:use_height
    let stdin = has_key(a:dict, 'source') ? '' : '< /dev/tty'
    call system(printf('tput cup %d > /dev/tty; tput cnorm > /dev/tty; %s %s 2> /dev/tty', &lines, command, stdin))
  else
    execute 'silent !'.command
  endif
  let exit_status = v:shell_error
  redraw!
  let lines = s:collect(a:temps)
  return s:exit_handler(a:dict, exit_status, command) < 2 ? lines : []
endfunction

function! s:calc_size(max, val, dict)
  let val = substitute(a:val, '^\~', '', '')
  if val =~ '%$'
    let size = a:max * str2nr(val[:-2]) / 100
  else
    let size = min([a:max, str2nr(val)])
  endif

  let srcsz = -1
  if type(get(a:dict, 'source', 0)) == type([])
    let srcsz = len(a:dict.source)
  endif

  let opts = $FZF_DEFAULT_OPTS.' '.s:evaluate_opts(get(a:dict, 'options', ''))
  if opts =~ 'preview'
    return size
  endif
  let margin = match(opts, '--inline-info\|--info[^-]\{-}inline') > match(opts, '--no-inline-info\|--info[^-]\{-}\(default\|hidden\)') ? 1 : 2
  let margin += match(opts, '--border\([^-]\|$\)') > match(opts, '--no-border\([^-]\|$\)') ? 2 : 0
  if stridx(opts, '--header') > stridx(opts, '--no-header')
    let margin += len(split(opts, "\n"))
  endif
  return srcsz >= 0 ? min([srcsz + margin, size]) : size
endfunction

function! s:getpos()
  return {'tab': tabpagenr(), 'win': winnr(), 'winid': win_getid(), 'cnt': winnr('$'), 'tcnt': tabpagenr('$')}
endfunction

function! s:border_opt(window)
  if type(a:window) != type({})
    return ''
  endif

  " Border style
  let style = tolower(get(a:window, 'border', ''))
  if !has_key(a:window, 'border') && has_key(a:window, 'rounded')
    let style = a:window.rounded ? 'rounded' : 'sharp'
  endif
  if style == 'none' || style == 'no'
    return ''
  endif

  " For --border styles, we need fzf 0.24.0 or above
  call fzf#exec('0.24.0')
  let opt = ' --border ' . style
  if has_key(a:window, 'highlight')
    let color = s:get_color('fg', a:window.highlight)
    if len(color)
      let opt .= ' --color=border:' . color
    endif
  endif
  return opt
endfunction

function! s:split(dict)
  let directions = {
        \ 'up':    ['topleft', 'resize', &lines],
        \ 'down':  ['botright', 'resize', &lines],
        \ 'left':  ['vertical topleft', 'vertical resize', &columns],
        \ 'right': ['vertical botright', 'vertical resize', &columns] 
        \}
  let ppos = s:getpos()
  let is_popup = 0
  try
    if s:present(a:dict, 'window')
      if type(a:dict.window) == type({})
        if !has('popupwin')
          throw 'Vim with popupwin feature is required for pop-up window'
        end
        call s:popup(a:dict.window)
        let is_popup = 1
      else
        execute 'keepalt' a:dict.window
      endif
    elseif !s:splittable(a:dict)
      execute (tabpagenr()-1).'tabnew'
    else
      for [dir, triple] in items(directions)
        let val = get(a:dict, dir, '')
        if !empty(val)
          let [cmd, resz, max] = triple
          if (dir == 'up' || dir == 'down') && val[0] == '~'
            let sz = s:calc_size(max, val, a:dict)
          else
            let sz = s:calc_size(max, val, {})
          endif
          execute cmd sz.'new'
          execute resz sz
          return [ppos, {}, is_popup]
        endif
      endfor
    endif
    return [ppos, is_popup ? {} : { '&l:wfw': &l:wfw, '&l:wfh': &l:wfh }, is_popup]
  finally
    if !is_popup
      setlocal winfixwidth winfixheight
    endif
  endtry
endfunction

let s:warned = 0
function! s:handle_ambidouble(dict)
  if &ambiwidth == 'double'
    let a:dict.env = { 'RUNEWIDTH_EASTASIAN': '1' }
  elseif !s:warned && $RUNEWIDTH_EASTASIAN == '1' && &ambiwidth !=# 'double'
    call fzf#utils#Warn("$RUNEWIDTH_EASTASIAN is '1' but &ambiwidth is not 'double'")
    2sleep
    let s:warned = 1
  endif
endfunction

function! s:execute_term(dict, command, temps) abort
  let winrest = winrestcmd()
  let pbuf = bufnr('')
  let [ppos, winopts, is_popup] = s:split(a:dict)
  let b:fzf = a:dict
  let fzf = { 'buf': bufnr(''), 'pbuf': pbuf, 'ppos': ppos, 'dict': a:dict, 'temps': a:temps,
        \ 'winopts': winopts, 'winrest': winrest, 'lines': &lines,
        \ 'columns': &columns, 'command': a:command }

  function! fzf.switch_back(inplace)
    if a:inplace && bufnr('') == self.buf
      if bufexists(self.pbuf)
        execute 'keepalt keepjumps b' self.pbuf
      endif
      " No other listed buffer
      if bufnr('') == self.buf
        enew
      endif
    endif
  endfunction

  function! fzf.on_exit(id, code, ...)
    if s:getpos() == self.ppos " {'window': 'enew'}
      for [opt, val] in items(self.winopts)
        execute 'let' opt '=' val
      endfor
      call self.switch_back(1)
    else
      if bufnr('') == self.buf
        " We use close instead of bd! since Vim does not close the split when
        " there's no other listed buffer ('set nobuflisted')
        close
      endif
      silent! execute 'tabnext' self.ppos.tab
      silent! execute self.ppos.win.'wincmd w'
    endif

    if bufexists(self.buf)
      execute 'bd!' self.buf
    endif

    if &lines == self.lines && &columns == self.columns && s:getpos() == self.ppos
      execute self.winrest
    endif

    let lines = s:collect(self.temps)
    if s:exit_handler(self.dict, a:code, self.command, 1) >= 2
      return
    endif

    call s:pushd(self.dict)
    call s:callback(self.dict, lines)
    call self.switch_back(s:getpos() == self.ppos)

    if &buftype == 'terminal'
      call feedkeys(&filetype == 'fzf' ? "\<Plug>(fzf-insert)" : "\<Plug>(fzf-normal)")
    endif
  endfunction

  try
    call s:pushd(a:dict)
    let command = a:command
    let command .= s:term_marker
    let term_opts = {'exit_cb': function(fzf.on_exit), 'term_kill': 'term'}
    if is_popup
      let term_opts.hidden = 1
    else
      let term_opts.curwin = 1
    endif
    call s:handle_ambidouble(term_opts)
    keepjumps let fzf.buf = term_start([&shell, &shellcmdflag, command], term_opts)
    if is_popup
      doautocmd <nomodeline> TerminalWinOpen
    endif
    tnoremap <buffer> <c-z> <nop>
    if empty(&termwinkey) || &termwinkey =~? '<c-w>'
      tnoremap <buffer> <c-w> <c-w>.
    endif
  finally
    call s:dopopd()
  endtry
  setlocal nospell bufhidden=wipe nobuflisted nonumber
  setf fzf
  startinsert
  return []
endfunction

function! s:collect(temps) abort
  try
    return filereadable(a:temps.result) ? readfile(a:temps.result) : []
  finally
    for tf in values(a:temps)
      silent! call delete(tf)
    endfor
  endtry
endfunction

function! s:callback(dict, lines) abort
  let popd = has_key(a:dict, 'pushd')
  if popd
    let w:fzf_pushd = a:dict.pushd
  endif

  try
    if has_key(a:dict, 'sink')
      for line in a:lines
        if type(a:dict.sink) == 2
          call a:dict.sink(line)
        else
          execute a:dict.sink fnameescape(line)
        endif
      endfor
    endif
    if has_key(a:dict, 'sink*')
      call a:dict['sink*'](a:lines)
    elseif has_key(a:dict, 'sinklist')
      call a:dict['sinklist'](a:lines)
    endif
  catch
    if stridx(v:exception, ':E325:') < 0
      echoerr v:exception
    endif
  endtry

  " We may have opened a new window or tab
  if popd
    let w:fzf_pushd = a:dict.pushd
    call s:dopopd()
  endif
endfunction

function! s:popup(opts) abort
  let xoffset = get(a:opts, 'xoffset', 0.5)
  let yoffset = get(a:opts, 'yoffset', 0.5)
  let relative = get(a:opts, 'relative', 0)

  " Use current window size for positioning relatively positioned popups
  let columns = relative ? winwidth(0) : &columns
  let lines = relative ? winheight(0) : &lines

  " Size and position
  let width = min([max([8, a:opts.width > 1 ? a:opts.width : float2nr(columns * a:opts.width)]), columns])
  let height = min([max([4, a:opts.height > 1 ? a:opts.height : float2nr(lines * a:opts.height)]), lines])
  let row = float2nr(yoffset * (lines - height)) + (relative ? win_screenpos(0)[0] : 1)
  let col = float2nr(xoffset * (columns - width)) + (relative ? win_screenpos(0)[1] : 1)

  " Managing the differences
  let row = min([max([0, row]), &lines - height])
  let col = min([max([0, col]), &columns - width])

  let s:popup_create = {buf -> popup_create(buf, #{
        \ line: row,
        \ col: col,
        \ minwidth: width,
        \ maxwidth: width,
        \ minheight: height,
        \ maxheight: height,
        \ zindex: 1000,
        \ })}

  autocmd TerminalOpen * ++once call s:popup_create(str2nr(expand('<abuf>')))
endfunction

let s:default_action = {
      \ 'ctrl-t': 'tab split',
      \ 'ctrl-x': 'split',
      \ 'ctrl-s': 'split',
      \ 'ctrl-v': 'vsplit' }

function! s:shortpath()
  let short = fnamemodify(getcwd(), ':~:.')
  if !has('win32unix')
    let short = pathshorten(short)
  endif
  let slash = '/'
  return empty(short) ? '~'.slash : short . (short =~ escape(slash, '\').'$' ? '' : slash)
endfunction

function! s:defs(commands)
  let prefix = fzf#utils#Conf('command_prefix', '')
  if prefix =~# '^[^A-Z]'
    echoerr 'g:fzf_command_prefix must start with an uppercase letter'
    return
  endif
  for command in a:commands
    let name = ':'.prefix.matchstr(command, '\C[A-Z]\S\+')
    if 2 != exists(name)
      execute substitute(command, '\ze\C[A-Z]', prefix, '')
    endif
  endfor
endfunction

call s:defs([
      \'command!      -bang -nargs=? -complete=dir Files      call fzf#vim#files(<q-args>, fzf#vim#with_preview(), <bang>0)',
      \'command! -bar -bang -nargs=? -complete=buffer Buffers call fzf#vim#buffers(<q-args>, fzf#vim#with_preview({ "placeholder": "{1}" }), <bang>0)',
      \'command! -bar -bang Colors                            call fzf#vim#colors(<bang>0)',
      \'command!      -bang -nargs=* Rg                       call fzf#vim#grep("rg --column --line-number --no-heading --color=always --smart-case -- ".shellescape(<q-args>), fzf#vim#with_preview(), <bang>0)',
      \'command! -bar -bang Snippets                          call fzf#vim#snippets(<bang>0)',
      \'command! -bar -bang Commands                          call fzf#vim#commands(<bang>0)',
      \'command! -bar -bang Helptags                          call fzf#vim#helptags(fzf#vim#with_preview({ "placeholder": "--tag {2}:{3}:{4}" }), <bang>0)',
      \])

if !exists('g:fzf#vim#buffers')
  let g:fzf#vim#buffers = {}
endif

augroup fzf_buffers
  autocmd!
  autocmd BufWinEnter,WinEnter * let g:fzf#vim#buffers[bufnr('')] = localtime()
  autocmd BufDelete * silent! call remove(g:fzf#vim#buffers, expand('<abuf>'))
augroup END
