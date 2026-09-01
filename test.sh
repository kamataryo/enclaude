#!/usr/bin/env bash
# dclaude worktree の後片付けを検証する。docker-compose はダミーに差し替えるので Docker は不要。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dclaude-test.XXXXXX")"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# ダミー docker-compose: run のとき FAKE_ACTION を worktree の中で実行するだけ
mkdir -p "$tmp/bin"
cat > "$tmp/bin/docker-compose" <<'EOF'
#!/bin/sh
while [ "${1:-}" = "-f" ]; do shift 2; done
[ "${1:-}" = "run" ] || exit 0
[ -n "${FAKE_ACTION:-}" ] && (cd "$WORKSPACE" && eval "$FAKE_ACTION")
exit 0
EOF
chmod +x "$tmp/bin/docker-compose"
export PATH="$tmp/bin:$PATH"

repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
echo hello > "$repo/a.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm init

fail=0
check() { if eval "$2"; then echo "  ok: $1"; else echo "  NG: $1"; fail=1; fi; }
wt() { (cd "$repo" && FAKE_ACTION="${2:-}" "$here/bin/dclaude" worktree "$1" >/dev/null); }

echo "変更なし → worktree もブランチも消える"
wt clean
check "worktree が消えている"  '[ ! -d "$tmp/wt_clean_repo" ]'
check "ブランチも消えている"    '! git -C "$repo" rev-parse --verify -q wt/dclaude/clean >/dev/null'

echo "コミットあり → worktree は消えるがブランチは残る"
wt done 'echo x >> a.txt; git add -A; git commit -qm work'
check "worktree が消えている"  '[ ! -d "$tmp/wt_done_repo" ]'
check "ブランチが残っている"    'git -C "$repo" rev-parse --verify -q wt/dclaude/done >/dev/null'

echo "未コミットあり → worktree ごと残る"
wt dirty 'echo x >> a.txt'
check "worktree が残っている"  '[ -d "$tmp/wt_dirty_repo" ]'
check "ブランチが残っている"    'git -C "$repo" rev-parse --verify -q wt/dclaude/dirty >/dev/null'
git -C "$repo" worktree remove --force "$tmp/wt_dirty_repo"

echo "補完スクリプトが両シェルで読める"
check "bash" 'bash -c "eval \"\$($here/bin/dclaude --completion)\" && complete -p dclaude >/dev/null"'
if command -v zsh >/dev/null; then
  check "zsh" 'zsh -c "autoload -U compinit; compinit -u -d $tmp/zcd >/dev/null 2>&1; eval \"\$($here/bin/dclaude --completion)\"; [[ \$(whence -w _dclaude) == *function ]]"'
else
  echo "  skip: zsh がないので省略"
fi

[ "$fail" -eq 0 ] && echo "全部通りました" || { echo "失敗あり" >&2; exit 1; }
