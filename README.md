# enclaudé

claude-code を Docker のサンドボックスで動かすラッパー

## 必要なもの

Docker / Docker Compose、pnpm、bash。

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
| `enclaudé worktree <name>` | `wt/enclaude/<name>` の worktree を作って起動。終了時に後片付け |
| `enclaudé self-update` | `pnpm update --latest` でロックを更新し、イメージを再ビルド |
| `enclaudé help` | enclaudé 自身のヘルプ。`--help` / `-h` は claude のヘルプ（そのまま渡る） |
| `enclaudé completion` | 補完スクリプトを出力 |

### worktree の後片付け

worktree は `<リポジトリの親>/wt_<name>_<リポジトリ名>` に作られ、終了時の状態で分岐する。

| 状態 | worktree | ブランチ |
|---|---|---|
| 未コミットの変更あり | 残す | 残す |
| コミット済み | 削除 | 残す |
| 変更もコミットもなし | 削除 | 削除 |
