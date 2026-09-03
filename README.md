# Claude Code enclavé, c'est *Enclaudé*.

Claude Code を Docker のサンドボックスで動かすラッパーです。

## できること / できないこと

### できること

- カレントディレクトリだけをマウントして Claude Code を隔離した環境で起動します
- ログイン状態や会話履歴は永続化されます（`home` ボリューム。プロジェクト単位ではなく enclaudé 全体で 1 つです）
- ホストの `~/.claude/CLAUDE.md` は読み取り専用で共有されます
- git リポジトリでは `git log` / `git diff` などの読み取り系が使えます（`git add` / `git commit` はできません）
- 終了時に、コンテナ内で書き換えられた・削除されたファイルを一覧します（gitignore されたものも含む）
- 足りないランタイムやツールは `Dockerfile.override` でイメージに重ねられます

### できないこと

- マウントしたディレクトリの外にあるホストのファイルの読み書き
- ホストの `~/.claude/settings.json` やスキル・エージェント類の引き継ぎ（必要な設定は `settings.override.json` に、プラグインは `Dockerfile.override` に書いてください）
- ホストのブラウザや GUI を必要とする機能（Claude in Chrome など。必要なときは、これらはホスト側の Claude Code で実行するのが簡単だと思います）
- Git や GitHub への書き込み操作（ホスト環境の Git の設定や、GitHub の認証情報は持ち込みません）
- コンテナを起動するようなタスク（Docker in Docker はありません）
- ネットワークの遮断（コンテナから外部へは自由に通信できます）
- プロジェクトごとのログイン情報・会話履歴の分離（`home` ボリュームは enclaudé を使う全プロジェクトで共有されるため、あるプロジェクトで動かしたコンテナから、別プロジェクトの会話履歴やログイン情報が見えます）

## 守れる範囲

コンテナの中の claude は、マウントしたディレクトリを自由に書き換えられます。プロンプトインジェクションを受けた場合、その書き換えがホスト側に残るということです。**マウントしたディレクトリの中身は信用できないものとして扱ってください。**

ホストで `git commit` した瞬間に走る `.git/hooks` と `.git/config` だけは読み取り専用でマウントして塞いでいます。ただし多層防御の一枚であって、境界ではありません。`package.json` の scripts、`Makefile`、`.envrc`、`.vscode/tasks.json`、`.github/workflows`、ソースコードそのものは書き換えられます。`home` ボリュームも全プロジェクト共有なので、汚染されると以後すべてのコンテナに効き続けます。

`git status` は gitignore されたファイルを見せず、一番危ないもの（`node_modules/`、`.env` など）ほど目に入りません。そこで終了時に、書き換えられたファイルをまとめて出します。

```
コンテナ内で書き換えられたファイル:
 deploy.sh                  | 0
 hidden.sh                  | 1 +
 innocent.conf              | 1 +
 node_modules/evil/index.js | 1 +
 4 files changed, 3 insertions(+)
 mode change 100644 => 100755 deploy.sh
 create mode 120000 innocent.conf
ホストの git が直接読むファイル:
./.git/hooks/pre-commit
./.git/modules/sub/hooks/pre-commit
削除されたファイル:
./.env
```

この報告は `enclaudé diff` でいつでも出し直せます（直前のセッションの範囲）。

この報告はコンテナが端末を握った後に出るため、大量の空行や ANSI エスケープで画面から流すことは原理的に防げません。疑わしいときはスクロールバックを遡ってください。

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

## 使い方

```shell
cd <作業ディレクトリ>
enclaudé # 初回起動時はコンテナが自動でビルドされます
```

| コマンド | 動作 |
|---|---|
| `enclaudé [args...]` | カレントディレクトリをマウントして起動します。引数はそのまま claude に渡ります |
| `enclaudé help` | enclaudé 自身のヘルプです。`--help` / `-h` は claude のヘルプ（そのまま渡ります） |
| `enclaudé completion` | 補完スクリプトを出力します |
| `enclaudé diff` | 直前のセッションのこの報告をもう一度表示します |
| `enclaudé edit` | `Dockerfile.override` を `$EDITOR` で開きます。無ければ `Dockerfile.override.sample` からコピーします |
| `enclaudé rebuild` | イメージを再ビルドします。`Dockerfile` や `Dockerfile.override` を変えたら実行してください |
| `enclaudé self-update` | claude-code を最新のバージョンに更新して、イメージを再ビルドします |
| `enclaudé destroy` | コンテナ・イメージ・ボリュームを削除します。ログイン状態も消えます |

- コンテナ自体がサンドボックスなので、`--dangerously-skip-permissions` を付けて起動します
- 初回起動時に Claude へのログインが求められます

## Claude の設定を上書きする（任意）

claude に渡す設定はリポジトリの `settings.json` に入っています。ホストの `~/.claude/settings.json` は持ち込まないので、必要な設定は `settings.override.json`（Git 管理外）に書いてください。起動時にマージされ、同じキーは override 側が勝ちます。

```shell
pushd /path/to/enclaude
cp ~/.claude/settings.json ./settings.override.json
vi ./settings.override.json # 必要なパラメータだけ残す
popd
```

ホスト固有のパス（`hooks` や `env` など）はコンテナ内では壊れた参照になるので、まるごとコピーせず必要な項目だけ残してください。

環境変数は `env` に書けばそのまま届きます。使える変数は [Environment variables](https://code.claude.com/docs/en/env-vars) にあります。ただし `CLAUDE_CONFIG_DIR` のようにファイルの置き場所を変える変数は、`home` ボリュームでの永続化と食い違うので変えないでください。

```json
{
  "env": {
    "API_TIMEOUT_MS": "1200000",
    "MAX_THINKING_TOKENS": "32000"
  }
}
```

## ランタイムやツールを追加する（任意）

イメージには Node.js と Git しか入っていません。PHP や Python など作業に必要なものは、`Dockerfile.override`（Git 管理外）でベースイメージの上に重ねられます。`settings.override.json` と同じく全プロジェクト共通です。

```shell
enclaudé edit     # $EDITOR で開きます。初回は Dockerfile.override.sample からコピーされます
enclaudé rebuild  # 作成・変更・削除のたびに必要です
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

### プラグインやスキルを焼き込む

ホストの `~/.claude/skills` や `~/.claude/agents` は持ち込みませんが、プラグインなら [プラグインシード](https://code.claude.com/docs/en/plugin-marketplaces#pre-populate-plugins-for-containers) でイメージに焼き込めます。

```dockerfile
FROM enclaude-base

RUN CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed \
      claude plugin marketplace add <owner>/<repo> \
 && CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed \
      claude plugin install <plugin>@<marketplace>

ENV CLAUDE_CODE_PLUGIN_SEED_DIR=/opt/claude-seed
```

シードは読み取り専用です。外したいときは `/plugin disable` を使うか、`Dockerfile.override` を書き換えて `enclaudé rebuild` してください。
