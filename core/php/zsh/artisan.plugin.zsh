# artisan en LAR corre con el php de esta shell. No pasa por Sail ni por
# docker compose: esta terminal ya está dentro del contenedor.

_artisan_find() {
  local dir=.
  until [[ $dir -ef / ]]; do
    if [[ -f $dir/artisan ]]; then
      print -r -- "$dir/artisan"
      return 0
    fi
    dir+=/..
  done
  return 1
}

artisan() {
  local artisan_path
  artisan_path=$(_artisan_find) || {
    print -u2 "artisan: no está en este proyecto."
    return 1
  }
  php "$artisan_path" "$@"
}

_artisan_add_completion() {
  local artisan_path
  artisan_path=$(_artisan_find) || return
  local -a commands
  commands=(${(f)"$(php "$artisan_path" --raw --no-ansi list 2>/dev/null | sed 's/[[:space:]].*//')"})
  (( ${#commands} )) && compadd -a commands
}

compdef _artisan_add_completion artisan
