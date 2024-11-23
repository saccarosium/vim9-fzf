" ------------------------------------------------------------------
" Common
" ------------------------------------------------------------------

let s:warned = 0
function! s:bash()
  if exists('s:bash')
    return s:bash
  endif

  let custom_bash = fzf#utils#Conf('preview_bash', '')
  let candidates = filter([custom_bash, 'bash'], 'len(v:val)')

  let found = filter(map(copy(candidates), 'exepath(v:val)'), 'len(v:val)')
  if empty(found)
    if !s:warned
      call s:warn(printf('Preview window not supported (%s not found)', join(candidates, ', ')))
      let s:warned = 1
    endif
    let s:bash = ''
    return s:bash
  endif

  let s:bash = found[0]

  return s:bash
endfunction

let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:p:h:h:h').'/bin/'
let s:bin = {'preview': s:bin_dir.'preview.sh', 'tags': s:bin_dir.'tags.pl'}
let s:TYPE = {'bool': type(0), 'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}

let s:wide = 120

function! s:escape_for_bash(path)
  if !exists('s:is_linux_like_bash')
    call system(s:bash . ' -c "ls /mnt/[A-Za-z]"')
    let s:is_linux_like_bash = v:shell_error == 0
  endif

  let path = substitute(a:path, '\', '/', 'g')
  if s:is_linux_like_bash
    let path = substitute(path, '^\([A-Z]\):', '/mnt/\L\1', '')
  endif

  return escape(path, ' ')
endfunction


function! s:extend_opts(dict, eopts, prepend)
  if empty(a:eopts)
    return
  endif
  if has_key(a:dict, 'options')
    if type(a:dict.options) == s:TYPE.list && type(a:eopts) == s:TYPE.list
      if a:prepend
        let a:dict.options = extend(copy(a:eopts), a:dict.options)
      else
        call extend(a:dict.options, a:eopts)
      endif
    else
      let all_opts = a:prepend ? [a:eopts, a:dict.options] : [a:dict.options, a:eopts]
      let a:dict.options = join(map(all_opts, 'type(v:val) == s:TYPE.list ? join(map(copy(v:val), "shellescape(v:val)")) : v:val'))
    endif
  else
    let a:dict.options = a:eopts
  endif
endfunction

function! s:merge_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 0)
endfunction

function! s:prepend_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 1)
endfunction

" [spec to wrap], [preview window expression], [toggle-preview keys...]
function! fzf#vim#with_preview(...)
  " Default spec
  let spec = {}
  let window = ''

  let args = copy(a:000)

  " Spec to wrap
  if len(args) && type(args[0]) == s:TYPE.dict
    let spec = copy(args[0])
    call remove(args, 0)
  endif

  if !executable(s:bash())
    return spec
  endif

  " Placeholder expression (TODO/TBD: undocumented)
  let placeholder = get(spec, 'placeholder', '{}')

  " g:fzf_preview_window
  if empty(args)
    let preview_args = fzf#utils#Conf('preview_window', ['', 'ctrl-/'])
    if empty(preview_args)
      let args = ['hidden']
    else
      " For backward-compatiblity
      let args = type(preview_args) == type('') ? [preview_args] : copy(preview_args)
    endif
  endif

  if len(args) && type(args[0]) == s:TYPE.string
    if len(args[0]) && args[0] !~# '^\(up\|down\|left\|right\|hidden\)'
      throw 'invalid preview window: '.args[0]
    endif
    let window = args[0]
    call remove(args, 0)
  endif

  let preview = []
  if len(window)
    let preview += ['--preview-window', window]
  endif

  let preview_cmd = s:bash() . ' ' . s:escape_for_bash(s:bin.preview)
  if len(placeholder)
    let preview += ['--preview', preview_cmd.' '.placeholder]
  end
  if &ambiwidth ==# 'double'
    let preview += ['--no-unicode']
  end

  if len(args)
    call extend(preview, ['--bind', join(map(args, 'v:val.":toggle-preview"'), ',')])
  endif
  call s:merge_opts(spec, preview)
  return spec
endfunction

function! s:remove_layout(opts)
  for key in s:layout_keys
    if has_key(a:opts, key)
      call remove(a:opts, key)
    endif
  endfor
  return a:opts
endfunction

function! s:reverse_list(opts)
  let tokens = map(split($FZF_DEFAULT_OPTS, '[^a-z-]'), 'substitute(v:val, "^--", "", "")')
  if index(tokens, 'reverse') < 0
    return extend(['--layout=reverse-list'], a:opts)
  endif
  return a:opts
endfunction

function! s:wrap(name, opts, bang)
  " fzf#wrap does not append --expect if sink or sink* is found
  let opts = copy(a:opts)
  let options = ''
  if has_key(opts, 'options')
    let options = type(opts.options) == s:TYPE.list ? join(opts.options) : opts.options
  endif
  if options !~ '--expect' && has_key(opts, 'sink*')
    let Sink = remove(opts, 'sink*')
    let wrapped = fzf#wrap(a:name, opts, a:bang)
    let wrapped['sink*'] = Sink
  else
    let wrapped = fzf#wrap(a:name, opts, a:bang)
  endif
  return wrapped
endfunction

function! s:strip(str)
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction

function! s:rstrip(str)
  return substitute(a:str, '\s*$', '', 'g')
endfunction

function! s:chomp(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:escape(path)
  let path = fnameescape(a:path)
  return path
endfunction

if v:version >= 704
  function! s:function(name)
    return function(a:name)
  endfunction
else
  function! s:function(name)
    " By Ingo Karkat
    return function(substitute(a:name, '^s:', matchstr(expand('<sfile>'), '<SNR>\d\+_\zefunction$'), ''))
  endfunction
endif

function! s:get_color(attr, ...)
  let gui = has('termguicolors') && &termguicolors
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

let s:ansi = {'black': 30, 'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36}

function! s:csi(color, fg)
  let prefix = a:fg ? '38;' : '48;'
  if a:color[0] == '#'
    return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
  endif
  return prefix.'5;'.a:color
endfunction

function! s:ansi(str, group, default, ...)
  let fg = s:get_color('fg', a:group)
  let bg = s:get_color('bg', a:group)
  let color = (empty(fg) ? s:ansi[a:default] : s:csi(fg, 1)) .
        \ (empty(bg) ? '' : ';'.s:csi(bg, 0))
  return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

for s:color_name in keys(s:ansi)
  execute "function! s:".s:color_name."(str, ...)\n"
        \ "  return s:ansi(a:str, get(a:, 1, ''), '".s:color_name."')\n"
        \ "endfunction"
endfor

function! s:buflisted()
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&filetype") != "qf"')
endfunction

function! s:fzf(name, opts, extra)

  let [extra, bang] = [{}, 0]
  if len(a:extra) <= 1
    let first = get(a:extra, 0, 0)
    if type(first) == s:TYPE.dict
      let extra = first
    else
      let bang = first
    endif
  elseif len(a:extra) == 2
    let [extra, bang] = a:extra
  else
    throw 'invalid number of arguments'
  endif

  let extra  = copy(extra)
  let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
  let merged = extend(copy(a:opts), extra)
  call s:merge_opts(merged, eopts)
  return fzf#run(s:wrap(a:name, merged, bang))
endfunction

let s:default_action = {
      \ 'ctrl-t': 'tab split',
      \ 'ctrl-x': 'split',
      \ 'ctrl-v': 'vsplit' }

function! s:execute_silent(cmd)
  silent keepjumps keepalt execute a:cmd
endfunction

" [key, [filename, [stay_on_edit: 0]]]
function! s:action_for(key, ...)
  let Cmd = get(get(g:, 'fzf_action', s:default_action), a:key, '')
  let cmd = type(Cmd) == s:TYPE.string ? Cmd : ''

  " See If the command is the default action that opens the selected file in
  " the current window. i.e. :edit
  let edit = stridx('edit', cmd) == 0 " empty, e, ed, ..

  " If no extra argument is given, we just execute the command and ignore
  " errors. e.g. E471: Argument required: tab drop
  if !a:0
    if !edit
      normal! m'
      silent! call s:execute_silent(cmd)
    endif
  else
    " For the default edit action, we don't execute the action if the
    " selected file is already opened in the current window, or we are
    " instructed to stay on the current buffer.
    let stay = edit && (a:0 > 1 && a:2 || fnamemodify(a:1, ':p') ==# expand('%:p'))
    if !stay
      normal! m'
      call s:execute_silent((len(cmd) ? cmd : 'edit').' '.s:escape(a:1))
    endif
  endif
endfunction

function! s:open(target)
  if fnamemodify(a:target, ':p') ==# expand('%:p')
    return
  endif
  execute 'edit' s:escape(a:target)
endfunction

function! s:align_lists(lists)
  let maxes = {}
  for list in a:lists
    let i = 0
    while i < len(list)
      let maxes[i] = max([get(maxes, i, 0), len(list[i])])
      let i += 1
    endwhile
  endfor
  for list in a:lists
    call map(list, "printf('%-'.maxes[v:key].'s', v:val)")
  endfor
  return a:lists
endfunction

function! s:warn(message)
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function! s:fill_quickfix(name, list)
  if len(a:list) > 1
    let Handler = fzf#utils#Conf('listproc_'.a:name, fzf#utils#Conf('listproc', function('fzf#vim#listproc#quickfix')))
    call call(Handler, [a:list], {})
    return 1
  endif
  return 0
endfunction

function! fzf#vim#_uniq(list)
  let visited = {}
  let ret = []
  for l in a:list
    if !empty(l) && !has_key(visited, l)
      call add(ret, l)
      let visited[l] = 1
    endif
  endfor
  return ret
endfunction

" ------------------------------------------------------------------
" Files
" ------------------------------------------------------------------

function! s:shortpath()
  let short = fnamemodify(getcwd(), ':~:.')
  if !has('win32unix')
    let short = pathshorten(short)
  endif
  let slash = '/'
  return empty(short) ? '~/' : short . (short =~ escape('/', '\').'$' ? '' : '/')
endfunction

function! fzf#vim#files(dir, ...)
  let args = {}
  if !empty(a:dir)
    if !isdirectory(expand(a:dir))
      return s:warn('Invalid directory')
    endif
    let dir = substitute(a:dir, '[/\\]*$', '/', '')
    let args.dir = dir
  else
    let dir = s:shortpath()
  endif

  let args.options = ['-m', '--prompt', strwidth(dir) < &columns / 2 - 20 ? dir : '> ']
  call s:merge_opts(args, fzf#utils#Conf('files_options', []))
  return s:fzf('files', args, a:000)
endfunction

" ------------------------------------------------------------------
" Buffers
" ------------------------------------------------------------------

function! s:find_open_window(b)
  let [tcur, tcnt] = [tabpagenr() - 1, tabpagenr('$')]
  for toff in range(0, tabpagenr('$') - 1)
    let t = (tcur + toff) % tcnt + 1
    let buffers = tabpagebuflist(t)
    for w in range(1, len(buffers))
      let b = buffers[w - 1]
      if b == a:b
        return [t, w]
      endif
    endfor
  endfor
  return [0, 0]
endfunction

function! s:jump(t, w)
  execute a:t.'tabnext'
  execute a:w.'wincmd w'
endfunction

function! s:bufopen(lines)
  if len(a:lines) < 2
    return
  endif
  let b = matchstr(a:lines[1], '\[\zs[0-9]*\ze\]')
  if empty(a:lines[0]) && fzf#utils#Conf('buffers_jump', 0)
    let [t, w] = s:find_open_window(b)
    if t
      call s:jump(t, w)
      return
    endif
  endif
  call s:action_for(a:lines[0])
  execute 'buffer' b
endfunction

function! fzf#vim#_format_buffer(b)
  let name = bufname(a:b)
  let line = exists('*getbufinfo') ? getbufinfo(a:b)[0]['lnum'] : 0
  let fullname = empty(name) ? '' : fnamemodify(name, ":p:~:.")
  let dispname = empty(name) ? '[No Name]' : name
  let flag = a:b == bufnr('')  ? s:blue('%', 'Conditional') :
        \ (a:b == bufnr('#') ? s:magenta('#', 'Special') : ' ')
  let modified = getbufvar(a:b, '&modified') ? s:red(' [+]', 'Exception') : ''
  let readonly = getbufvar(a:b, '&modifiable') ? '' : s:green(' [RO]', 'Constant')
  let extra = join(filter([modified, readonly], '!empty(v:val)'), '')
  let target = empty(name) ? '' : (line == 0 ? fullname : fullname.':'.line)
  return s:rstrip(printf("%s\t%d\t[%s] %s\t%s\t%s", target, line, s:yellow(a:b, 'Number'), flag, dispname, extra))
endfunction

function! s:sort_buffers(...)
  let [b1, b2] = map(copy(a:000), 'get(g:fzf#vim#buffers, v:val, v:val)')
  " Using minus between a float and a number in a sort function causes an error
  return b1 < b2 ? 1 : -1
endfunction

function! fzf#vim#_buflisted_sorted()
  return sort(s:buflisted(), 's:sort_buffers')
endfunction

" [query (string)], [bufnrs (list)], [spec (dict)], [fullscreen (bool)]
function! fzf#vim#buffers(...)
  let [query, args] = (a:0 && type(a:1) == type('')) ?
        \ [a:1, a:000[1:]] : ['', a:000]
  if len(args) && type(args[0]) == s:TYPE.list
    let [buffers; args] = args
  else
    let buffers = s:buflisted()
  endif
  let sorted = sort(buffers, 's:sort_buffers')
  let header_lines = '--header-lines=' . (bufnr('') == get(sorted, 0, 0) ? 1 : 0)
  let tabstop = len(max(sorted)) >= 4 ? 9 : 8
  return s:fzf('buffers', {
        \ 'source':  map(sorted, 'fzf#vim#_format_buffer(v:val)'),
        \ 'sink*':   s:function('s:bufopen'),
        \ 'options': ['+m', '-x', '--tiebreak=index', header_lines, '--ansi', '-d', '\t', '--with-nth', '3..', '-n', '2,1..2', '--prompt', 'Buf> ', '--query', query, '--preview-window', '+{2}-/2', '--tabstop', tabstop]
        \}, args)
endfunction

" ------------------------------------------------------------------
" Ag / Rg
" ------------------------------------------------------------------

function! s:ag_to_qf(line)
  let parts = matchlist(a:line, '\(.\{-}\)\s*:\s*\(\d\+\)\%(\s*:\s*\(\d\+\)\)\?\%(\s*:\(.*\)\)\?')
  let file = &acd ? fnamemodify(parts[1], ':p') : parts[1]
  if has('win32unix') && file !~ '/'
    let file = substitute(file, '\', '/', 'g')
  endif
  let dict = {'filename': file, 'lnum': parts[2], 'text': parts[4]}
  if len(parts[3])
    let dict.col = parts[3]
  endif
  return dict
endfunction

function! s:ag_handler(name, lines)
  if len(a:lines) < 2
    return
  endif

  let multi_line = min([fzf#utils#Conf('grep_multi_line', 0), 1])
  let lines = []
  if multi_line && executable('perl')
    for idx in range(1, len(a:lines), multi_line + 1)
      call add(lines, join(a:lines[idx:idx + multi_line], ''))
    endfor
  else
    let lines = a:lines[1:]
  endif

  let list = map(filter(lines, 'len(v:val)'), 's:ag_to_qf(v:val)')
  if empty(list)
    return
  endif

  call s:action_for(a:lines[0], list[0].filename, len(list) > 1)
  if s:fill_quickfix(a:name, list)
    return
  endif

  " Single item selected
  let first = list[0]
  try
    execute first.lnum
    if has_key(first, 'col')
      call cursor(0, first.col)
    endif
    normal! zvzz
  catch
  endtry
endfunction

" query, [ag options], [spec (dict)], [fullscreen (bool)]
function! fzf#vim#ag(query, ...)
  if type(a:query) != s:TYPE.string
    return s:warn('Invalid query argument')
  endif
  let query = empty(a:query) ? '^(?=.)' : a:query
  let args = copy(a:000)
  let ag_opts = len(args) > 1 && type(args[0]) == s:TYPE.string ? remove(args, 0) : ''
  let command = ag_opts . ' -- ' . shellescape(query)
  return call('fzf#vim#ag_raw', insert(args, command, 0))
endfunction

" ag command suffix, [spec (dict)], [fullscreen (bool)]
function! fzf#vim#ag_raw(command_suffix, ...)
  if !executable('ag')
    return s:warn('ag is not found')
  endif
  return call('fzf#vim#grep', extend(['ag --nogroup --column --color '.a:command_suffix, 1], a:000))
endfunction

function! s:grep_multi_line(opts)
  " TODO: Non-global option
  let multi_line = fzf#utils#Conf('grep_multi_line', 0)
  if multi_line && executable('perl')
    let opts = copy(a:opts)
    let extra = ['--read0', '--highlight-line']
    if multi_line > 1
      call extend(extra, ['--gap', multi_line - 1])
    endif
    let opts.options = extend(copy(opts.options), extra)
    return [opts, printf(" | perl -pe 's/\\n/%s/; s/^([^:]+:){2,3}/$&\\n  /'", '\0')]
  endif

  return [a:opts, '']
endfunction

" command (string), [spec (dict)], [fullscreen (bool)]
function! fzf#vim#grep(grep_command, ...)
  let args = copy(a:000)
  let words = []
  for word in split(a:grep_command)
    if word !~# '^[a-z]'
      break
    endif
    call add(words, word)
  endfor
  let words   = empty(words) ? ['grep'] : words
  let name    = join(words, '-')
  let capname = join(map(words, 'toupper(v:val[0]).v:val[1:]'), '')
  let opts = {
        \ 'options': ['--ansi', '--prompt', capname.'> ',
        \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
        \             '--delimiter', ':', '--preview-window', '+{2}-/2']
        \}
  if len(args) && type(args[0]) == s:TYPE.bool
    call remove(args, 0)
  endif

  function! opts.sink(lines) closure
    return s:ag_handler(get(opts, 'name', name), a:lines)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  let [opts, suffix] = s:grep_multi_line(opts)
  let command = a:grep_command . suffix
  try
    let prev_default_command = $FZF_DEFAULT_COMMAND
    let $FZF_DEFAULT_COMMAND = command
    return s:fzf(name, opts, args)
  finally
    let $FZF_DEFAULT_COMMAND = prev_default_command
  endtry
endfunction


" command_prefix (string), initial_query (string), [spec (dict)], [fullscreen (bool)]
function! fzf#vim#grep2(command_prefix, query, ...)
  let args = copy(a:000)
  let words = []
  for word in split(a:command_prefix)
    if word !~# '^[a-z]'
      break
    endif
    call add(words, word)
  endfor
  let words = empty(words) ? ['grep'] : words
  let name = join(words, '-')
  let fallback = ' || :'
  let opts = {
        \ 'source': ':',
        \ 'options': ['--ansi', '--prompt', toupper(name).'> ', '--query', a:query,
        \             '--disabled',
        \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
        \             '--delimiter', ':', '--preview-window', '+{2}-/2']
        \}

  let [opts, suffix] = s:grep_multi_line(opts)
  let suffix = escape(suffix, '{')
  call extend(opts.options, ['--bind', 'start:reload:'.a:command_prefix.' '.shellescape(a:query).suffix])
  call extend(opts.options, ['--bind', 'change:reload:'.a:command_prefix.' {q}'.suffix.fallback])

  if len(args) && type(args[0]) == s:TYPE.bool
    call remove(args, 0)
  endif
  function! opts.sink(lines) closure
    return s:ag_handler(name, a:lines)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  return s:fzf(name, opts, args)
endfunction

" ------------------------------------------------------------------
" Commands
" ------------------------------------------------------------------

let s:tab = "\t"

function! s:format_cmd(line)
  return substitute(a:line, '\C \([A-Z]\S*\) ',
        \ '\=s:tab.s:yellow(submatch(1), "Function").s:tab', '')
endfunction

function! s:command_sink(lines)
  if len(a:lines) < 2
    return
  endif
  let cmd = matchstr(a:lines[1], s:tab.'\zs\S*\ze'.s:tab)
  if empty(a:lines[0])
    call feedkeys(':'.cmd.(a:lines[1][0] == '!' ? '' : ' '), 'n')
  else
    call feedkeys(':'.cmd."\<cr>", 'n')
  endif
endfunction

let s:fmt_excmd = '   '.s:blue('%-38s', 'Statement').'%s'

function! s:format_excmd(ex)
  let match = matchlist(a:ex, '^|:\(\S\+\)|\s*\S*\(.*\)')
  return printf(s:fmt_excmd, s:tab.match[1].s:tab, s:strip(match[2]))
endfunction

function! s:excmds()
  let help = globpath($VIMRUNTIME, 'doc/index.txt')
  if empty(help)
    return []
  endif

  let commands = []
  let command = ''
  for line in readfile(help)
    if line =~ '^|:[^|]'
      if !empty(command)
        call add(commands, s:format_excmd(command))
      endif
      let command = line
    elseif line =~ '^\s\+\S' && !empty(command)
      let command .= substitute(line, '^\s*', ' ', '')
    elseif !empty(commands) && line =~ '^\s*$'
      break
    endif
  endfor
  if !empty(command)
    call add(commands, s:format_excmd(command))
  endif
  return commands
endfunction

function! fzf#vim#commands(...)
  redir => cout
  silent command
  redir END
  let list = split(cout, "\n")
  return s:fzf('commands', {
        \ 'source':  extend(extend(list[0:0], map(list[1:], 's:format_cmd(v:val)')), s:excmds()),
        \ 'sink*':   s:function('s:command_sink'),
        \ 'options': '--ansi --expect '.fzf#utils#Conf('commands_expect', 'ctrl-x').
        \            ' --tiebreak=index --header-lines 1 -x --prompt "Commands> " -n2,3,2..3 --tabstop=1 -d "\t"'}, a:000)
endfunction

" ------------------------------------------------------------------
" Help tags
" ------------------------------------------------------------------

function! s:helptag_sink(line)
  let [tag, file, path] = split(a:line, "\t")[0:2]
  let rtp = fnamemodify(path, ':p:h:h')
  if stridx(&rtp, rtp) < 0
    execute 'set rtp+='.s:escape(rtp)
  endif
  execute 'help' tag
endfunction

function! fzf#vim#helptags(...)
  if !executable('perl')
    return s:warn('Helptags command requires perl')
  endif
  let sorted = sort(split(globpath(&runtimepath, 'doc/tags', 1), '\n'))
  let tags = exists('*uniq') ? uniq(sorted) : fzf#vim#_uniq(sorted)

  if exists('s:helptags_script')
    silent! call delete(s:helptags_script)
  endif
  let s:helptags_script = tempname()

  call writefile(['for my $filename (@ARGV) { open(my $file,q(<),$filename) or die; while (<$file>) { /(.*?)\t(.*?)\t(.*)/; push @lines, sprintf(qq('.s:green('%-40s', 'Label').'\t%s\t%s\t%s\n), $1, $2, $filename, $3); } close($file) or die; } print for sort @lines;'], s:helptags_script)
  return s:fzf('helptags', {
        \ 'source': 'perl '.shellescape(s:helptags_script).' '.join(map(tags, 'shellescape(v:val)')),
        \ 'sink':    s:function('s:helptag_sink'),
        \ 'options': ['--ansi', '+m', '--tiebreak=begin', '--with-nth', '..3']}, a:000)
endfunction
