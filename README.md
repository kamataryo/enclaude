# enclaudé

claude-code を Docker のサンドボックスで動かすラッパー。隔離されているので `--dangerously-skip-permissions` が実用的に使える。

> 名前はフランス語の過去分詞めかした綴り。実行ファイルだけアクセント付き、パッケージ名やブランチ名は `enclaude`。

## 必要なもの

Docker / Docker Compose、pnpm、bash。

## インストール

```sh
git clone git@github.com:kamataryo/enclaude.git
```

`.zshrc`（bash なら `.bashrc`）に追記する。

```sh
export PATH="/path/to/enclaude/bin:$PATH"
eval "$(enclaudé --completion)"          # 補完。bash / zsh 両対応
```

シェルを開き直してからイメージを用意する。

```sh
cd /path/to/enclaude
pnpm install --lockfile-only   # ロックだけ作る。ホストに node_modules は要らない
docker-compose build
```

初回起動時はコンテナ内で `/login` が必要（ホストの Keychain は読めないため）。認証は named volume に残るので次回以降は不要。

## 使い方

| | |
|---|---|
| `enclaudé [args...]` | カレントディレクトリをマウントして起動。引数はそのまま claude に渡る |
| `enclaudé worktree <name>` | `wt/enclaude/<name>` の worktree を作って起動。終了時に後片付け |
| `enclaudé self-update` | `pnpm update --latest` でロックを更新し、イメージを再ビルド |
| `enclaudé help` | enclaudé 自身のヘルプ。`--help` / `-h` は claude のヘルプ（そのまま渡る） |
| `enclaudé --completion` | 補完スクリプトを出力 |

### worktree の後片付け

worktree は `<リポジトリの親>/wt_<name>_<リポジトリ名>` に作られ、終了時の状態で分岐する。

| 状態 | worktree | ブランチ |
|---|---|---|
| 未コミットの変更あり | 残す | 残す |
| コミット済み | 削除 | 残す |
| 変更もコミットもなし | 削除 | 削除 |

### プラグイン

プラグインは `settings.json` では管理しない。宣言しても実体が取得されず、下のコマンドが同じキーを `~/.claude/settings.json` に書くため二重になる。

```sh
enclaudé plugin marketplace add DietrichGebert/ponytail
enclaudé plugin install ponytail@ponytail
```

インストール先は `~/.claude/plugins/` で volume に残るため、実行は volume を作り直したときの一度だけでよい。ホスト側とは別管理なのでバージョンもずれる。

## 構成

| | |
|---|---|
| ベース | `node:22-slim` + git |
| claude-code | `pnpm-lock.yaml` でバージョン固定。`/opt/enclaude` に入れて `claude` にリンク |
| ロックの移植性 | ロックは全プラットフォームの optional 依存を持つ。Mac で生成しても Linux ビルド時に `linux-*` が選ばれるのでクロスインストールは不要 |
| 実行ユーザー | `node`（root だと `--dangerously-skip-permissions` が使えない） |
| 永続化 | named volume `home` に `/home/node` ごと。コンテナ自体は毎回使い捨て |
| 設定 | ホストの `~/.claude/CLAUDE.md` を read-only。`settings.json` は `claude --settings` で読ませる |
| 隔離範囲 | マウントしたディレクトリのみホストに書き込まれる。それ以外のホストは触れない |

永続化の単位が `.claude` ではなく `/home/node` なのは、オンボーディング状態とプロジェクト履歴が `~/.claude.json`（`.claude` の外のファイル）に保存されるため。`.claude` だけを volume にすると毎回初回起動になる。

ホストの `~/.claude/settings.json` はマウントしていない。`statusLine` がホスト絶対パスを参照し、`sandbox.enabled` がコンテナ内で二重サンドボックスになるため。

### settings.json の反映

リポジトリの `settings.json` を編集すれば次の起動で反映される。`/mnt/settings.json` に read-only で渡し、ENTRYPOINT の `claude --settings /mnt/settings.json` が読む。コピーではなく直接読ませているので、claude 自身が書いた `theme` などはコンテナ側に残り、逆にリポジトリの `settings.json` に書いたキーはコンテナ内で変更しても次の起動で戻る。

ENTRYPOINT に固定しているため、compose を通さず素の `docker run` をするとこのファイルが無くて起動できない。

なお `.npmrc` の `minimum-release-age=43200` で、公開から 30 日経ったバージョンのみ入る。

## テスト

```sh
./test.sh
```

worktree の後片付け（3 分岐）と補完スクリプトを検証する。`docker-compose` をダミーに差し替えるので Docker は不要で、`git` と `bash` だけで走る（zsh がなければその項目はスキップ）。CI でもそのまま動く（`.github/workflows/test.yml`）。逆に言うと、コンテナの中身は検証していない。

## やっていないこと

- ネットワーク制限なし。`npm install` も WebFetch も素通り
- 会話履歴・plugins はホストと共有しない
- マウントしたディレクトリはホスト実体なので、そこだけは保護されない
