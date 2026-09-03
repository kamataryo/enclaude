#!/bin/sh
# enclaudé の help と補完スクリプトを検証する。Docker は不要。
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/enclaude-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { if eval "$2"; then echo "  ok: $1"; else echo "  NG: $1"; fail=1; fi; }

echo "help は claude に渡らず自前で表示する"
check "destroy の行がある" '"$here/bin/enclaudé" help | grep -q "enclaudé destroy"'
check "rebuild の行がある" '"$here/bin/enclaudé" help | grep -q "enclaudé rebuild"'
check "edit の行がある" '"$here/bin/enclaudé" help | grep -q "enclaudé edit"'
check "self-update の行がある" '"$here/bin/enclaudé" help | grep -q "enclaudé self-update"'

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

echo "lock_version がロックから claude-code のバージョンを抜く"
# ファイル全体を読み込むと末尾の case が走ってしまうので、関数の定義行だけを取り出して評価する
eval "$(grep '^lock_version()' "$here/bin/enclaudé")"
check "セマンティックバージョンが取れる" 'lock_version "$here/pnpm-lock.yaml" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"'

echo "補完スクリプトが両シェルで読める"
check "bash" 'bash -c "eval \"\$($here/bin/enclaudé completion)\" && complete -p enclaudé >/dev/null"'
if command -v zsh >/dev/null; then
  check "zsh" 'zsh -c "autoload -U compinit; compinit -u -d $tmp/zcd >/dev/null 2>&1; eval \"\$($here/bin/enclaudé completion)\"; [[ \$(whence -w _enclaude) == *function ]]"'
else
  echo "  skip: zsh がないので省略"
fi

echo ".git/config と .git/hooks を ro で重ねる"
# docker を差し替えて、compose run に渡る引数だけを見る（コンテナは起動しない）
mkdir -p "$tmp/bin" "$tmp/proj/.git/hooks" "$tmp/plain"
: > "$tmp/proj/.git/config"
printf '#!/bin/sh\necho "$@"\n' > "$tmp/bin/docker"
chmod +x "$tmp/bin/docker"
args() { (cd "$1" && PATH="$tmp/bin:$PATH" HOME="$tmp" "$here/bin/enclaudé"); }
check "config が ro で渡る" 'args "$tmp/proj" | grep -q -- "-v $tmp/proj/.git/config:$tmp/proj/.git/config:ro"'
check "hooks が ro で渡る" 'args "$tmp/proj" | grep -q -- "-v $tmp/proj/.git/hooks:$tmp/proj/.git/hooks:ro"'
check "サービス名の前に並ぶ" 'args "$tmp/proj" | grep -qE -- "(-v [^ ]+:ro ){2}claude$"'
check "git 管理外なら足さない" '! args "$tmp/plain" | grep -q -- "-v $tmp/plain"'


echo "終了後に書き換えられたファイルを報告する"
# スタブの docker が compose run のときだけ、いろいろ書き換える
cat > "$tmp/bin/docker" <<'STUB'
#!/bin/sh
echo "$@"
case " $* " in *" run "*) ;; *) exit 0 ;; esac
mkdir -p node_modules && echo x > node_modules/evil.js
rm -f gone.txt
ln -s /etc/passwd evil-link
if [ -d .git ]; then
  mkdir -p .git/hooks .git/modules/sub/hooks
  echo x > .git/hooks/pre-commit
  echo x > .git/modules/sub/hooks/pre-commit
fi
# mtime を 2020 年に偽装する（ctime は戻せないので検出できるはず）
touch -t 202001010000 ref.tmp && echo p > hidden.sh && touch -r ref.tmp hidden.sh && rm -f ref.tmp
# 一覧を溢れさせて本命を押し出す隠蔽
[ -f .flood ] && { i=0; while [ $i -lt 205 ]; do echo x > "flood$i.txt"; i=$((i + 1)); done; }
exit 0
STUB
chmod +x "$tmp/bin/docker"
if command -v git >/dev/null; then
  git init -q "$tmp/proj"
  printf 'node_modules/\n' > "$tmp/proj/.gitignore"
  echo x > "$tmp/proj/gone.txt"
  args "$tmp/proj" > "$tmp/report.txt"
  check "gitignore 済みでも --stat に出る" 'grep -qE "node_modules/evil\.js +\| +1 \+" "$tmp/report.txt"'
  check "削除されたファイルも出る" 'grep -q "^\./gone\.txt$" "$tmp/report.txt"'
  check ".git/hooks も出る" 'grep -q "^\./\.git/hooks/pre-commit$" "$tmp/report.txt"'
  check "submodule の hooks も出る" 'grep -q "^\./\.git/modules/sub/hooks/pre-commit$" "$tmp/report.txt"'
  check "mtime を偽装しても出る" 'grep -q "hidden\.sh" "$tmp/report.txt"'
  check "symlink も出る" 'grep -q "evil-link" "$tmp/report.txt"'
else
  echo "  skip: git がないので省略"
fi
mkdir -p "$tmp/flood" && : > "$tmp/flood/.flood"
check "打ち切ったら件数を言う" 'args "$tmp/flood" | grep -q "件を省略"'
check "git 管理外なら一覧を出す" 'args "$tmp/plain" | grep -q "./node_modules/evil.js"'

[ "$fail" -eq 0 ] && echo "全部通りました" || { echo "失敗あり" >&2; exit 1; }
