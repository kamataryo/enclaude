#!/bin/sh
# enclaudé の help と補完スクリプトを検証する。Docker は不要。
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
# macOS の TMPDIR は末尾が / なので、そのままだとパスに // が混ざって文字列比較がずれる
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/enclaude-test.XXXXXX")" && pwd)"
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
printf '#!/bin/sh\necho "TZ=$TZ" "$@"\n' > "$tmp/bin/docker"
chmod +x "$tmp/bin/docker"
args() { (cd "$1" && PATH="$tmp/bin:$PATH" HOME="$tmp" "$here/bin/enclaudé"); }
check "config が ro で渡る" 'args "$tmp/proj" | grep -q -- "-v $tmp/proj/.git/config:$tmp/proj/.git/config:ro"'
check "hooks が ro で渡る" 'args "$tmp/proj" | grep -q -- "-v $tmp/proj/.git/hooks:$tmp/proj/.git/hooks:ro"'
check "サービス名の前に並ぶ" 'args "$tmp/proj" | grep -qE -- "(-v [^ ]+:ro ){2}claude$"'
check "git 管理外なら足さない" '! args "$tmp/plain" | grep -q -- "-v $tmp/plain"'

echo "hooks ディレクトリが無くても ro で重ねる"
mkdir -p "$tmp/nohooks/.git"
: > "$tmp/nohooks/.git/config"
check "hooks が ro で渡る" 'args "$tmp/nohooks" | grep -q -- "-v $tmp/nohooks/.git/hooks:$tmp/nohooks/.git/hooks:ro"'
check "空の hooks を作る" '[ -d "$tmp/nohooks/.git/hooks" ]'

echo "危険なディレクトリでは起動しない"
check "\$HOME は落ちる" '! args "$tmp" >/dev/null 2>&1'
check "docker は呼ばれない" '[ -z "$(args "$tmp" 2>/dev/null)" ]'
check "/ は落ちる" '! args / >/dev/null 2>&1'
check "\$HOME の親も落ちる" '! (cd "$tmp/proj" && PATH="$tmp/bin:$PATH" HOME="$tmp/proj/sub" "$here/bin/enclaudé") >/dev/null 2>&1'

echo "ホストのタイムゾーンをコンテナへ渡す"
check "TZ があればそのまま渡る" 'TZ=Asia/Tokyo args "$tmp/proj" | grep -q "^TZ=Asia/Tokyo "'
check "TZ が無ければ localtime から拾う" '(unset TZ; ln -sf /x/zoneinfo/Asia/Tokyo "$tmp/lt"; readlink "$tmp/lt" | sed -n "s|.*/zoneinfo/||p") | grep -q "^Asia/Tokyo$"'

echo "worktree では本体の gitdir を ro で足す"
if command -v git >/dev/null; then
  git init -q "$tmp/wtmain"
  (cd "$tmp/wtmain" \
    && git -c user.email=a@b -c user.name=a commit -q --allow-empty -m init \
    && git worktree add -q "$tmp/wt" -b wt)
  # 実装と同じ手順で期待値を出す（macOS の /var -> /private/var のような差を吸収する）
  common="$(cd "$tmp/wt" && cd "$(git rev-parse --git-common-dir)" && pwd)"
  check "本体の gitdir が ro で渡る" 'args "$tmp/wt" | grep -q -- "-v $common:$common:ro"'
  check "rw では渡さない" '! args "$tmp/wt" | grep -qE -- "-v $common:$common( |$)"'
  check "通常のリポジトリには足さない" '! args "$tmp/proj" | grep -q -- "-v $tmp/proj/.git:"'
else
  echo "  skip: git がないので省略"
fi

echo "core.hooksPath がワークスペース内を指すなら ro で重ねる"
if command -v git >/dev/null; then
  hooks_path_repo() { git init -q "$tmp/$1"; git -C "$tmp/$1" config core.hooksPath "$2"; mkdir -p "$tmp/$1/$2"; }
  hooks_path_repo husky9 .husky/_
  hooks_path_repo husky8 .husky
  git init -q "$tmp/outside"
  mkdir -p "$tmp/ext"
  git -C "$tmp/outside" config core.hooksPath "$tmp/ext"
  check "husky v9 は親の .husky ごと渡る" 'args "$tmp/husky9" | grep -q -- "-v $tmp/husky9/.husky:$tmp/husky9/.husky:ro"'
  check "husky v8 も渡る" 'args "$tmp/husky8" | grep -q -- "-v $tmp/husky8/.husky:$tmp/husky8/.husky:ro"'
  check "ワークスペースの外は足さない" '! args "$tmp/outside" | grep -q -- "$tmp/ext"'
  check "設定が無ければ足さない" '! args "$tmp/proj" | grep -q -- "husky"'
else
  echo "  skip: git がないので省略"
fi

[ "$fail" -eq 0 ] && echo "全部通りました" || { echo "失敗あり" >&2; exit 1; }
