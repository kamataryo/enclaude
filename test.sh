#!/bin/sh
# enclaudé の help と補完スクリプトを検証する。Docker は不要。
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
# enclaudé はワークスペースを pwd -P で解くので、期待値も揃える
# （macOS の TMPDIR は末尾が / で、しかも /var -> /private/var のリンク越し）
tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/enclaude-test.XXXXXX")" && pwd -P)"
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

echo ".git を丸ごと ro で重ねる"
# docker を差し替えて、compose run に渡る引数だけを見る（コンテナは起動しない）
mkdir -p "$tmp/bin" "$tmp/proj/.git" "$tmp/plain"
: > "$tmp/proj/.git/config"
printf '#!/bin/sh\necho "TZ=$TZ" "$@"\n' > "$tmp/bin/docker"
chmod +x "$tmp/bin/docker"
args() { (cd "$1" && PATH="$tmp/bin:$PATH" HOME="$tmp" "$here/bin/enclaudé"); }
check ".git が ro で渡る" 'args "$tmp/proj" | grep -q -- "-v $tmp/proj/.git:$tmp/proj/.git:ro"'
check "サービス名の前に並ぶ" 'args "$tmp/proj" | grep -qE -- "-v [^ ]+:ro claude$"'
check "git 管理外なら足さない" '! args "$tmp/plain" | grep -q -- "-v $tmp/plain"'

echo "危険なディレクトリでは起動しない"
check "\$HOME は落ちる" '! args "$tmp" >/dev/null 2>&1'
check "docker は呼ばれない" '[ -z "$(args "$tmp" 2>/dev/null)" ]'
check "/ は落ちる" '! args / >/dev/null 2>&1'
check "\$HOME の親も落ちる" '! (cd "$tmp/proj" && PATH="$tmp/bin:$PATH" HOME="$tmp/proj/sub" "$here/bin/enclaudé") >/dev/null 2>&1'
ln -s "$tmp" "$tmp/proj/homelink"
check "リンク経由の \$HOME も落ちる" '! args "$tmp/proj/homelink" >/dev/null 2>&1'
mkdir -p "$tmp/a:b"
check ": を含むパスは落ちる" '! args "$tmp/a:b" >/dev/null 2>&1'

echo "ホストのタイムゾーンをコンテナへ渡す"
check "TZ があればそのまま渡る" 'TZ=Asia/Tokyo args "$tmp/proj" | grep -q "^TZ=Asia/Tokyo "'
if [ -L /etc/localtime ]; then
  eval "$(grep '^host_tz()' "$here/bin/enclaudé")"
  check "TZ が無ければ localtime のリンク先から拾う" 'tz="$(unset TZ; host_tz)" && [ -n "$tz" ] && readlink /etc/localtime | grep -q "/zoneinfo/$tz$"'
else
  echo "  skip: /etc/localtime がリンクでないので省略"
fi

echo "worktree / submodule では、確かめたうえで本体の gitdir を ro で足す"
if command -v git >/dev/null; then
  git init -q "$tmp/wtmain"
  (cd "$tmp/wtmain" \
    && git -c user.email=a@b -c user.name=a commit -q --allow-empty -m init \
    && git worktree add -q "$tmp/wt" -b wt)
  common="$tmp/wtmain/.git"
  check "本体の gitdir が ro で渡る" 'args "$tmp/wt" | grep -q -- "-v $common:$common:ro"'
  check "rw では渡さない" '! args "$tmp/wt" | grep -qE -- "-v $common:$common( |$)"'
  check ".git ファイル自体も ro で渡る" 'args "$tmp/wt" | grep -q -- "-v $tmp/wt/.git:$tmp/wt/.git:ro"'
  check "通常のリポジトリには足さない" '! args "$tmp/proj" | grep -q -- "-v $common:"'
  # コンテナの中から .git ファイルを書き換えて、無関係なリポジトリを指させた場合
  git init -q "$tmp/secret"
  mkdir -p "$tmp/hijack"
  echo "gitdir: $tmp/secret/.git" > "$tmp/hijack/.git"
  check "別リポジトリの .git を指させても足さない" '! args "$tmp/hijack" 2>/dev/null | grep -q -- "$tmp/secret"'
  # 中に偽の gitdir を作り、指し返しを偽装したうえで commondir で別リポジトリへ飛ばす場合
  mkdir -p "$tmp/hijack2/fake"
  cp "$tmp/secret/.git/HEAD" "$tmp/hijack2/fake/"
  echo "$tmp/secret/.git" > "$tmp/hijack2/fake/commondir"
  echo "$tmp/hijack2/.git" > "$tmp/hijack2/fake/gitdir"
  echo "gitdir: $tmp/hijack2/fake" > "$tmp/hijack2/.git"
  check "偽の gitdir + commondir でも足さない" '! args "$tmp/hijack2" 2>/dev/null | grep -q -- "$tmp/secret"'
  git init -q "$tmp/sub"
  git -C "$tmp/sub" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
  git init -q "$tmp/super"
  git -C "$tmp/super" -c protocol.file.allow=always submodule add -q "$tmp/sub" m 2>/dev/null
  check "submodule の gitdir が ro で渡る" 'args "$tmp/super/m" | grep -q -- "-v $tmp/super/.git/modules/m:$tmp/super/.git/modules/m:ro"'
else
  echo "  skip: git がないので省略"
fi

echo ".git/commondir を置かれても、ホストの git に config / hooks を差し替えさせない"
# 実際のガードは .git 全体の ro マウント。ここではそれが要る理由（commondir が効くこと）を固定しておく
if command -v git >/dev/null; then
  git init -q "$tmp/cd"
  mkdir -p "$tmp/cd/evil/objects" "$tmp/cd/evil/refs"
  cp "$tmp/cd/.git/HEAD" "$tmp/cd/evil/"
  printf '[core]\n\trepositoryformatversion = 0\n[user]\n\tname = evil\n' > "$tmp/cd/evil/config"
  echo ../evil > "$tmp/cd/.git/commondir"
  check "commondir の先の config が読まれる（= .git ごと守る必要がある）" '[ "$(git -C "$tmp/cd" config user.name)" = evil ]'
  check "その .git も丸ごと ro で渡る" 'args "$tmp/cd" | grep -q -- "-v $tmp/cd/.git:$tmp/cd/.git:ro"'
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
