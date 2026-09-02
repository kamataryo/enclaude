# Claude Code enclavé, c'est *Enclaudé*.

Claude Code を Docker のサンドボックスで動かすラッパーです。

## できること / できないこと

### できること

- カレントディレクトリだけをマウントして Claude Code を隔離した環境で起動します
- ログイン状態や会話履歴は永続化されます
- ホストの `~/.claude/CLAUDE.md` は読み取り専用で共有されます
- 足りないランタイムやツールは `Dockerfile.override` でイメージに重ねられます

### できないこと

- マウントしたディレクトリの外にあるホストのファイルの読み書き
- ホストの `~/.claude/settings.json` やスキル・エージェント類の引き継ぎ（必要な設定は `settings.override.json` に書いてください）
- ホストのブラウザや GUI を必要とする機能（Claude in Chrome など）
- Git や GitHub の操作（ホスト環境の Git の設定や、GitHub の認証情報は持ち込みません）
- コンテナを起動するようなタスク（Docker in Docker はありません）
- ネットワークの遮断（コンテナから外部へは自由に通信できます）

## 動作環境

- Mac => OK
- Linux => 多分 OK
- Windows => 未検証

## 必要なもの

- Docker

## インストール

```shell
git clone git@github.com:kamataryo/enclaude.git
```

以下を `.zshrc`（bash なら `.bashrc`）に追記します。`/path/to/enclaude` は `git clone` したパスに読み替えてください。

```shell
export PATH="/path/to/enclaude/bin:$PATH"
eval "$(enclaudé completion)" # 補完。bash / zsh 両対応
```

### Claude の設定を上書きする（任意）

claude に渡す設定はリポジトリの `settings.json` に入っています。ホストの `~/.claude/settings.json` はコンテナから見えない設定としているため、持ち込みたい設定がある場合は `settings.override.json`（Git 管理外）に書いてください。
起動時に `settings.json` へ重ねてマージされ、同じキーは override 側が勝ちます。

```shell
pushd /path/to/enclaude
cp ~/.claude/settings.json ./settings.override.json
vi ./settings.override.json # 必要なパラメータだけ残す
popd
```

ホスト固有のパス（`hooks` や `env` など）はコンテナ内では壊れた参照になるので、まるごとコピーせず必要な項目だけ残してください。

### ランタイムやツールを追加する（任意）

イメージには Node.js と Git しか入っていません。PHP や Python など作業に必要なものは、`Dockerfile.override`（Git 管理外）でベースイメージの上に重ねられます。

```shell
enclaudé edit     # $EDITOR で開きます。初回は Dockerfile.override.sample からコピーされます
enclaudé rebuild
```

```dockerfile
FROM enclaude-base

# apt を使うので root に切り替え、最後に node へ戻します
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends php-cli \
 && rm -rf /var/lib/apt/lists/*
USER node
```

`Dockerfile.override` があると、enclaudé はまずリポジトリの `Dockerfile` を `enclaude-base` としてビルドし、その上に `Dockerfile.override` を重ねたイメージで起動します。無ければ今までどおり `Dockerfile` だけでビルドします。

- 作ったとき・書き換えたとき・消したときは `enclaudé rebuild` が必要です
- `settings.override.json` と同じく全プロジェクト共通です。プロジェクトごとに中身を変えることはできません

## 使い方

```shell
cd <作業ディレクトリ>
enclaudé # 初回起動はコンテナが自動でビルドされます
```

| コマンド| 動作 |
|---|---|
| `enclaudé [args...]` | カレントディレクトリをマウントして起動します。引数はそのまま claude に渡ります |
| `enclaudé help` | enclaudé 自身のヘルプです。`--help` / `-h` は claude のヘルプ（そのまま渡ります） |
| `enclaudé completion` | 補完スクリプトを出力します |
| `enclaudé edit` | `Dockerfile.override` を `$EDITOR` で開きます。無ければ `Dockerfile.override.sample` からコピーします |
| `enclaudé rebuild` | イメージを再ビルドします。`Dockerfile` や `Dockerfile.override` を変えたら実行してください |
| `enclaudé destroy` | コンテナ・イメージ・ボリュームを削除します。ログイン状態も消えます |

- ホストの `~/.claude/CLAUDE.md` が空の場合、自動で空のファイルを作成します
- コンテナ自体がサンドボックスなので、`--dangerously-skip-permissions` を付けて起動します
- 初回起動時に Claude へのログインが求められます
- Claude Code の自動アップデートは `DISABLE_AUTOUPDATER=1` で無効化しています。アップデートしたい場合は、以下の手順でアップデートしてください

### claude-code を更新する

`pnpm-lock.yaml` でバージョンを固定しているので、ロックを更新してイメージを再ビルドします。

```shell
pushd /path/to/enclaude
pnpm update --latest --lockfile-only   # 最新に上げる。範囲内で引き直すだけなら pnpm install --lockfile-only
enclaudé rebuild
popd
```
