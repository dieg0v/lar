# artisan in LAR runs with this shell's php. It does not go through Sail or
# docker compose: this terminal is already inside the container.

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
    print -u2 "artisan: it is not in this project."
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
