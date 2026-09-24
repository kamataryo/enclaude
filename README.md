# Claude Code enclavé, c'est *Enclaudé*.

Claude Code を Docker のサンドボックスで動かすラッパーです。

## できること / できないこと

### できること

- カレントディレクトリだけをマウントして Claude Code を隔離した環境で起動します
- ログイン状態や会話履歴は永続化されます（`home` ボリューム。プロジェクト単位ではなく enclaudé 全体で 1 つです）
- ホストの `~/.claude/CLAUDE.md` は読み取り専用で共有されます
- git リポジトリでは `git log` / `git diff` などの読み取り系が使えます（`git add` / `git commit` もコンテナの中では通ります。worktree / submodule だけは本体の gitdir を ro で重ねるため落ちます）
- 足りないランタイムやツールは `Dockerfile.override` でイメージに重ねられます

### できないこと

- マウントしたディレクトリの外にあるホストのファイルの読み書き
- ホストの `~/.claude/settings.json` やスキル・エージェント類の引き継ぎ（必要な設定は `settings.override.json` に、プラグインは `Dockerfile.override` に書いてください）。なお claude.ai アカウントで有効にしたスキルとプラグインは、ログインしたコンテナにも同期されます。止めたいときは `settings.override.json` に `"syncClaudeAiSkills": false` / `"syncClaudeAiPlugins": false` を書いてください
- ホストのブラウザや GUI を必要とする機能（Claude in Chrome など。必要なときは、これらはホスト側の Claude Code で実行するのが簡単だと思います）
- Git や GitHub への書き込み操作（ホスト環境の Git の設定や、GitHub の認証情報は持ち込みません）
- `/` や `$HOME`（とその親）での起動。ホストの資格情報がまるごと rw で入ってしまうので、起動時に拒否します
- コンテナを起動するようなタスク（Docker in Docker はありません）
- ネットワークの遮断（コンテナから外部へは自由に通信できます）
- プロジェクトごとのログイン情報・会話履歴の分離（`home` ボリュームは enclaudé を使う全プロジェクトで共有されるため、あるプロジェクトで動かしたコンテナから、別プロジェクトの会話履歴やログイン情報が見えます）

## 守れる範囲

コンテナの中の claude は、マウントしたディレクトリを自由に書き換えられます。プロンプトインジェクションを受けた場合、その書き換えがホスト側に残るということです。**マウントしたディレクトリの中身は信用できないものとして扱ってください。**

塞いでいるのは、ホスト側で勝手に実行されるもののうち git のフック周りだけです。読み取り専用でマウントします。

- `.git/config` と `.git/hooks`（ホストで `git commit` した瞬間に走るもの）。hooks ディレクトリが無いリポジトリでは、空で作ってから重ねます
- `core.hooksPath` がワークスペースの中を指している場合（husky など）はその参照先も。husky v9 のように `.husky/_` を指す構成では、ラッパーが呼び出す親の `.husky/` ごと重ねます

ただし多層防御の一枚であって、境界ではありません。次のものは書き換えられます。

- `package.json` の scripts、`Makefile`、`.envrc`、`.vscode/tasks.json`、`.github/workflows`、ソースコードそのもの
- `.claude/settings.json` と `.claude/settings.local.json`。ホスト側でそのディレクトリを開いて Claude Code を起動した時点で hooks が走ります
- `.mcp.json`。同じく、ホストで起動した時点で MCP サーバーの `command` が実行されます

下の 2 つは `git commit` より発火が早い（ホストで `claude` と打っただけで走る）ので、`.git` 周りより危険だと考えてください。

ガード自体が届かないところもあります。

- enclaudé 自身のリポジトリ。ワークスペースに含めて起動すると、コンテナの中から `bin/enclaudé` を書き換えられます。ホストの PATH に入っているので、次の起動でホスト上で実行されます（自分自身を開発できるように、あえて拒否していません）
- ワークスペースの中にネストした独立リポジトリの `.git`
- `~/.claude.json` は読み取り専用にできないので、ユーザースコープの MCP サーバー登録は `home` ボリューム経由で以後のコンテナにも残ります
- `home` ボリュームは全プロジェクト共有なので、汚染されると以後すべてのコンテナに効き続けます

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

環境変数は `env` に書けばそのまま届きます。使える変数は [Environment variables](https://code.claude.com/docs/en/env-vars) にあります。ただし `CLAUDE_CONFIG_DIR` のようにファイルの置き場所を変える変数は、`home` ボリュームでの永続化と食い違うので変えないでください。また、`compose.yml` の `environment` で渡している `TZ` と `DISABLE_UPDATES` は起動時の環境変数が優先されるため、`env` に書いても効きません。

```json
{
  "env": {
    "API_TIMEOUT_MS": "1200000",
    "MAX_THINKING_TOKENS": "32000"
  }
}
```

## ランタイムやツールを追加する（任意）

イメージに入っているのは Node.js、Git、Python 3（`python3` と `uv`。pip はシステムには無いので、`python3 -m venv` か `uv` で環境を切って使います）と、基本的な CLI（`curl` / `less` / `ps` / `rg` / `jq` / `zip` / `unzip` / `file`）だけです。PHP や Go など作業に必要なものは、`Dockerfile.override`（Git 管理外）でベースイメージの上に重ねられます。`settings.override.json` と同じく全プロジェクト共通です。

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
