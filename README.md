# dclaude

claude-code を Docker のサンドボックスで動かす最小構成と、その CLI。

## セットアップ

```sh
pnpm install --lockfile-only   # ロックだけ作る。ホストに node_modules は要らない
docker-compose build
export PATH="$PWD/bin:$PATH"          # .zshrc などに追記
eval "$(dclaude --completion)"        # 補完（bash / zsh 両対応）
```

初回起動時はコンテナ内で `/login` が必要（ホストの Keychain は読めないため）。認証は named volume に残るので次回以降は不要。

## コマンド

| | |
|---|---|
| `dclaude [args...]` | カレントディレクトリをマウントして起動。引数はそのまま claude に渡る |
| `dclaude worktree <name>` | `wt/dclaude/<name>` の worktree を作って起動。終了時に後片付け |
| `dclaude self-update` | `pnpm update --latest` でロックを更新し、イメージを再ビルド |
| `dclaude --completion` | 補完スクリプトを出力 |

隔離されているので `dclaude --dangerously-skip-permissions` が実用的に使える。

### worktree の後片付け

終了時の状態で分岐する。

| 状態 | worktree | ブランチ |
|---|---|---|
| 未コミットの変更あり | 残す | 残す |
| コミット済み | 削除 | 残す |
| 変更もコミットもなし | 削除 | 削除 |

worktree は `<リポジトリの親>/wt_<name>_<リポジトリ名>` に作られる。

## 構成

| | |
|---|---|
| ベース | `node:22-slim` + git |
| claude-code | `pnpm-lock.yaml` でバージョン固定。`/opt/dclaude` に入れて `claude` にリンク |
| ロックの移植性 | ロックは全プラットフォームの optional 依存を持つ。Mac で生成しても Linux ビルド時に `linux-*` が選ばれるのでクロスインストールは不要 |
| 実行ユーザー | `node`（root だと `--dangerously-skip-permissions` が使えない） |
| 永続化 | named volume `home` に `/home/node` ごと。コンテナ自体は毎回使い捨て |
| 設定 | ホストの `~/.claude/CLAUDE.md` を read-only。`settings.json` は起動のたびに entrypoint がマージ |
| 隔離範囲 | マウントしたディレクトリのみホストに書き込まれる。それ以外のホストは触れない |

ホストの `~/.claude/settings.json` はマウントしていない。`statusLine` がホスト絶対パスを参照し、`sandbox.enabled` がコンテナ内で二重サンドボックスになるため。

永続化の単位が `.claude` ではなく `/home/node` なのは、オンボーディング状態とプロジェクト履歴が `~/.claude.json`（`.claude` の外のファイル）に保存されるため。`.claude` だけを volume にすると毎回初回起動になる。

### settings.json の反映

リポジトリの `settings.json` を編集すれば次の起動で反映される。`/mnt/settings.json` に read-only で渡し、entrypoint がコンテナ側へマージする（**ホスト側が優先**、それ以外の既存キーは保持）。

単一ファイルをそのまま `~/.claude/settings.json` に bind mount しない理由は、claude が atomic write（tmp に書いて rename）を使うため。bind mount された単一ファイルは rename で置換できず `Device or resource busy` になる。

マージ方式なので、claude 自身が書いた `theme` などはコンテナ側に残る。逆にホストの `settings.json` に書いたキーは、コンテナ内で変更しても次の起動で戻る。

`.npmrc` の `minimum-release-age=43200` で、公開から 30 日経ったバージョンのみ入る。

## テスト

```sh
./test.sh
```

worktree の後片付け（3分岐）と補完スクリプトを検証する。`docker-compose` をダミーに差し替えるので Docker は不要、`git` と `bash` だけで走る。zsh がなければその項目はスキップする。

Docker に依存しないので CI でもそのまま動く（`.github/workflows/test.yml`）。逆に言うと、コンテナの中身は検証していない。

## やっていないこと

- ネットワーク制限なし。`npm install` も WebFetch も素通り
- 会話履歴・plugins はホストと共有しない
- マウントしたディレクトリはホスト実体なので、そこだけは保護されない
