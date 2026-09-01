# enclaudé

claude-code を Docker のサンドボックスで動かすラッパー。

## 必要なもの

- Docker
- Docker Compose
- bash
- Git

## インストール

```sh
git clone git@github.com:kamataryo/enclaude.git
```

`.zshrc`（bash なら `.bashrc`）に追記する。

```sh
export PATH="/path/to/enclaude/bin:$PATH"
eval "$(enclaudé completion)"          # 補完。bash / zsh 両対応
```

シェルを開き直してからイメージを用意する。

```sh
cd /path/to/enclaude
pnpm install --lockfile-only   # ロックだけ作る。ホストに node_modules は要らない
docker-compose build
```

## 使い方

| | |
|---|---|
| `enclaudé [args...]` | カレントディレクトリをマウントして起動。引数はそのまま claude に渡る |
| `enclaudé self-update` | `pnpm update --latest` でロックを更新し、イメージを再ビルド |
| `enclaudé help` | enclaudé 自身のヘルプ。`--help` / `-h` は claude のヘルプ（そのまま渡る） |
| `enclaudé completion` | 補完スクリプトを出力 |

※ ホストの `~/.claude/CLAUDE.md` が空の場合、自動で空のファイルを作成します

### worktree で並行作業する

`enclaudé` はカレントディレクトリをマウントするだけなので、worktree の中で普通に起動すればよい。

```sh
git worktree add -b wt/foo ../wt_foo && pushd ../wt_foo && enclaudé ; popd
```

片付けは `git worktree remove ../wt_foo`。
