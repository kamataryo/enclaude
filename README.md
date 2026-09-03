# Claude Code enclavé, c'est *Enclaudé*.

Claude Code を Docker のサンドボックスで動かすラッパーです。

## できること / できないこと

### できること

- カレントディレクトリだけをマウントして Claude Code を隔離した環境で起動します
- ログイン状態や会話履歴は永続化されます（`home` ボリューム。プロジェクト単位ではなく enclaudé 全体で 1 つです）
- ホストの `~/.claude/CLAUDE.md` は読み取り専用で共有されます
- git リポジトリなら、`.git/config` と `.git/hooks` は読み取り専用でマウントします（[守れる範囲](#守れる範囲)）
- 終了時に、コンテナ内で書き換えられた・削除されたファイルを一覧します（gitignore されたものも含む。[守れる範囲](#守れる範囲)）
- 足りないランタイムやツールは `Dockerfile.override` でイメージに重ねられます

### できないこと

- マウントしたディレクトリの外にあるホストのファイルの読み書き
- ホストの `~/.claude/settings.json` やスキル・エージェント類の引き継ぎ（必要な設定は `settings.override.json` に、プラグインは `Dockerfile.override` に書いてください）
- ホストのブラウザや GUI を必要とする機能（Claude in Chrome など。必要なときは、これらはホスト側の Claude Code で実行するのが簡単だと思います）
- Git や GitHub の操作（ホスト環境の Git の設定や、GitHub の認証情報は持ち込みません）
- コンテナを起動するようなタスク（Docker in Docker はありません）
- ネットワークの遮断（コンテナから外部へは自由に通信できます）
- プロジェクトごとのログイン情報・会話履歴の分離（`home` ボリュームは enclaudé を使う全プロジェクトで共有されるため、あるプロジェクトで動かしたコンテナから、別プロジェクトの会話履歴やログイン情報が見えます）

## 守れる範囲

コンテナの中の claude は、マウントしたディレクトリを自由に書き換えられます。プロンプトインジェクションを受けた場合、その書き換えがホスト側に残るということです。

このうち `.git/hooks` と `.git/config` だけは、ホストで `git commit` した瞬間に実行されてしまうため、読み取り専用でマウントしています。`core.hooksPath` や `.gitattributes` の filter ドライバの定義先も `.git/config` なので、まとめて塞がります。代わりにコンテナ内から `git config` でローカル設定を書き換えることはできません。`.git` がファイルになる worktree や submodule では対象が見つからないため、このガードは効きません。

ただしこれは多層防御の一枚であって、境界ではありません。ホストであとから実行されるものは他にもあります。

- `package.json` の scripts、`Makefile`、`.envrc`、`.vscode/tasks.json`、`.github/workflows`、そしてソースコードそのもの
- `home` ボリュームの中身（`~/.claude/settings.json` の hooks など）。全プロジェクト共有なので、汚染されると以後すべてのコンテナに効き続けます

マウントしたディレクトリの中身は信用できないものとして扱ってください。とはいえ `git status` は gitignore されたファイルを見せないので、一番危ないもの（`node_modules/`、`.env`、`.claude/settings.local.json`、この repo なら `Dockerfile.override` や `settings.override.json`）ほど目に入りません。そこで終了時に、コンテナ内で書き換えられたファイルを `git diff --stat` の形式でまとめて出します。

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

- 検出は mtime ではなく **ctime** で行います。mtime は `touch -r` で戻せますが、ctime を任意の値にする手段はユーザー空間にありません。`chmod +x` しただけの変更や、シンボリックリンクへの差し替えもこれで出ます
- 一覧は 200 件で切りますが、切ったときは「ほか N 件を省略」と必ず出します。黙って切ると、ゴミを大量に書いて本命を一覧の外へ押し出す隠蔽が成立するためです
- 削除は起動時のファイル一覧との差分で出します
- gitignore 済みや untracked のファイルは、一時 index に intent-to-add して差分を取っています。ホスト側の index やステージング状態には触りません
- `.git/` は基本的に無視しますが、hooks と config は別枠で出します（submodule の `.git/modules/<name>/hooks/` も含む）。上の ro マウントが効かない worktree / submodule では、ここが唯一の気付く手段になるためです
- 残る弱点は、報告が出る前にコンテナが端末を握っていることです。大量の空行や ANSI エスケープを吐けば報告を画面から流せます。ここは原理的に塞げないので、疑わしいときはスクロールバックを遡ってください

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

#### 環境変数を渡す

claude の挙動を変える環境変数は、`settings.override.json` の `env` に書けばそのまま届きます。`compose.yml` を編集する必要はありません。

```json
{
  "env": {
    "API_TIMEOUT_MS": "1200000",
    "MAX_THINKING_TOKENS": "32000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  }
}
```

使える変数は [Environment variables](https://code.claude.com/docs/en/env-vars) にあります。ただし `CLAUDE_CONFIG_DIR` や `CLAUDE_CODE_TMPDIR` のようにファイルの置き場所を変える変数は、コンテナの永続化（`home` ボリューム）と食い違うので変えないでください。`DISABLE_UPDATES` は enclaudé が `compose.yml` で立てています（バージョンは `pnpm-lock.yaml` で固定し、更新は `enclaudé self-update` で行うため）。

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

#### プラグインやスキルを焼き込む

ホストの `~/.claude/skills` や `~/.claude/agents` は持ち込みませんが、プラグインなら `Dockerfile.override` でイメージに焼き込めます。claude にはコンテナ向けの [プラグインシード](https://code.claude.com/docs/en/plugin-marketplaces#pre-populate-plugins-for-containers) があり、ビルド時に置いたものを起動時に clone せずそのまま使います。

```dockerfile
FROM enclaude-base

RUN CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed \
      claude plugin marketplace add <owner>/<repo> \
 && CLAUDE_CODE_PLUGIN_CACHE_DIR=/opt/claude-seed \
      claude plugin install <plugin>@<marketplace>

ENV CLAUDE_CODE_PLUGIN_SEED_DIR=/opt/claude-seed
```

シードは読み取り専用で、コンテナ内から `/plugin marketplace remove` や `update` はできません。外したいときは `/plugin disable` を使うか、`Dockerfile.override` を書き換えて `enclaudé rebuild` してください。

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
| `enclaudé edit` | `Dockerfile.override` を `$EDITOR` で開きます。無ければ `Dockerfile.override.sample` からコピーします |
| `enclaudé rebuild` | イメージを再ビルドします。`Dockerfile` や `Dockerfile.override` を変えたら実行してください |
| `enclaudé self-update` | claude-code を最新のバージョンに更新して、イメージを再ビルドします |
| `enclaudé destroy` | コンテナ・イメージ・ボリュームを削除します。ログイン状態も消えます |

- ホストの `~/.claude/CLAUDE.md` が空の場合、自動で空のファイルを作成します
- コンテナ自体がサンドボックスなので、`--dangerously-skip-permissions` を付けて起動します
- 初回起動時に Claude へのログインが求められます
- Claude Code の更新は `enclaudé self-update` で行ってください

### claude-code を更新する

```shell
enclaudé self-update
```

公開直後のバージョンを掴まないよう、`pnpm-workspace.yaml` の `minimumReleaseAge`（分）で 1 日の待機を設けています。
