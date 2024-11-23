vim9script

export def Error(msg: string)
  echohl ErrorMsg
  echom msg
  echohl None
enddef

export def Warn(msg: string)
  echohl WarningMsg
  echom msg
  echohl None
enddef

export def Conf(name: string, default: any): any
  var conf = get(g:, 'fzf_vim', {})
  return get(conf, name, get(g:, $'fzf_{name}', default))
enddef
