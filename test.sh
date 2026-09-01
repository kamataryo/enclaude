#!/usr/bin/env bash
# enclaudé の help と補完スクリプトを検証する。Docker は不要。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/enclaude-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { if eval "$2"; then echo "  ok: $1"; else echo "  NG: $1"; fail=1; fi; }

echo "help は claude に渡らず自前で表示する"
check "self-update の行がある" '"$here/bin/enclaudé" help | grep -q "enclaudé self-update"'

echo "補完スクリプトが両シェルで読める"
check "bash" 'bash -c "eval \"\$($here/bin/enclaudé completion)\" && complete -p enclaudé >/dev/null"'
if command -v zsh >/dev/null; then
  check "zsh" 'zsh -c "autoload -U compinit; compinit -u -d $tmp/zcd >/dev/null 2>&1; eval \"\$($here/bin/enclaudé completion)\"; [[ \$(whence -w _enclaude) == *function ]]"'
else
  echo "  skip: zsh がないので省略"
fi

[ "$fail" -eq 0 ] && echo "全部通りました" || { echo "失敗あり" >&2; exit 1; }
