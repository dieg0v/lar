# LAR p85 n22 /path : branch*
# Backgrounds: LAR magenta, PHP cyan, Node green.
# Path in green. Branch in magenta, with * when there are changes.

lar_git() {
  command git -c safe.directory='*' "$@"
}

lar_prompt() {
  local node_ver node_short php_short branch
  print -Pn "%K{magenta}%F{white} LAR %k%f"

  php_short=""
  if [[ -n ${LAR_PHP_VERSION:-} ]]; then
    php_short="p${LAR_PHP_VERSION//./}"
  fi

  node_ver=$(node -v 2>/dev/null) || node_ver=""
  node_short=""
  if [[ -n $node_ver ]]; then
    node_short="n${${node_ver#v}%%.*}"
  fi

  if [[ -n $php_short ]]; then
    print -Pn "%K{cyan}%F{black} ${php_short} %k%f"
  fi
  if [[ -n $node_short ]]; then
    print -Pn "%K{green}%F{black} ${node_short} %k%f"
  fi

  print -Pn "%F{green}${(%):-%~}%f"

  if lar_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(lar_git symbolic-ref --short HEAD 2>/dev/null) \
      || branch=$(lar_git rev-parse --short HEAD 2>/dev/null) \
      || branch=""
    if [[ -n $branch ]]; then
      if [[ -n $(lar_git status --porcelain --ignore-submodules=dirty 2>/dev/null) ]]; then
        branch="${branch}*"
      fi
      print -Pn " %F{magenta}: ${branch}%f"
    fi
  fi
}

setopt prompt_subst
PROMPT='$(lar_prompt)
%F{magenta}%#%f '
