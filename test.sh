#!/usr/bin/env bash
# enclaudé の help と補完スクリプトを検証する。Docker は不要。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/enclaude-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { if eval "$2"; then echo "  ok: $1"; else echo "  NG: $1"; fail=1; fi; }

echo "help は claude に渡らず自前で表示する"
check "destroy の行がある" '"$here/bin/enclaudé" help | grep -q "enclaudé destroy"'

echo "destroy は N なら何もしない"
check "中止する" 'echo n | "$here/bin/enclaudé" destroy | grep -q 中止'

echo "settings.json と settings.override.json をマージする"
if command -v node >/dev/null; then
  printf '%s' '{"model":"opus","permissions":{"allow":["Bash"]}}'    > "$tmp/base.json"
  printf '%s' '{"model":"sonnet","permissions":{"deny":["WebFetch"]}}' > "$tmp/over.json"
  printf '%s' '{'                                                    > "$tmp/broken.json"
  merge() { node "$here/merge-settings.mjs" "$@" 2>/dev/null; }
  check "同じキーは override が勝つ" 'merge "$tmp/base.json" "$tmp/over.json" | grep -q "\"model\": \"sonnet\""'
  check "オブジェクトは再帰的にマージする" 'merge "$tmp/base.json" "$tmp/over.json" | grep -q Bash'
  check "壊れた override は無視する" 'merge "$tmp/base.json" "$tmp/broken.json" | grep -q "\"model\": \"opus\""'
  check "無いファイルは無視する" 'merge "$tmp/base.json" "$tmp/none.json" | grep -q "\"model\": \"opus\""'
else
  echo "  skip: node がないので省略"
fi

echo "補完スクリプトが両シェルで読める"
check "bash" 'bash -c "eval \"\$($here/bin/enclaudé completion)\" && complete -p enclaudé >/dev/null"'
if command -v zsh >/dev/null; then
  check "zsh" 'zsh -c "autoload -U compinit; compinit -u -d $tmp/zcd >/dev/null 2>&1; eval \"\$($here/bin/enclaudé completion)\"; [[ \$(whence -w _enclaude) == *function ]]"'
else
  echo "  skip: zsh がないので省略"
fi

[ "$fail" -eq 0 ] && echo "全部通りました" || { echo "失敗あり" >&2; exit 1; }
