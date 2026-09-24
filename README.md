# Claude Code enclavé, c'est *Enclaudé*.

Claude Code を Docker のサンドボックスで動かすラッパーです。

## できること / できないこと

### できること

- カレントディレクトリだけをマウントして Claude Code を隔離した環境で起動します
- ログイン状態や会話履歴は永続化されます（`home` ボリューム。プロジェクト単位ではなく enclaudé 全体で 1 つです）
- ホストの `~/.claude/CLAUDE.md` は読み取り専用で共有されます
- git リポジトリでは `git log` / `git diff` などの読み取り系が使えます（`.git` を読み取り専用で重ねるので、`git add` / `git commit` は通りません。worktree / submodule でも同じです）
- 足りないランタイムやツールは `Dockerfile.override` でイメージに重ねられます
- GitHub の Issue の読み書き（任意。リポジトリごとに `enclaudé gh-token` でトークンを登録したときだけ。[後述](#github-の-issue-を読み書きする任意)）

### できないこと

- マウントしたディレクトリの外にあるホストのファイルの読み書き
- ホストの `~/.claude/settings.json` やスキル・エージェント類の引き継ぎ（必要な設定は `settings.override.json` に、プラグインは `Dockerfile.override` に書いてください）。なお claude.ai アカウントで有効にしたスキルとプラグインは、ログインしたコンテナにも同期されます。止めたいときは `settings.override.json` に `"syncClaudeAiSkills": false` / `"syncClaudeAiPlugins": false` を書いてください
- ホストのブラウザや GUI を必要とする機能（Claude in Chrome など。必要なときは、これらはホスト側の Claude Code で実行するのが簡単だと思います）
- Git や GitHub への書き込み操作（`add` / `commit` / `push`、PR の作成など。ホスト環境の Git の設定や、GitHub の認証情報も持ち込みません。例外は上の Issue の読み書きだけです）
- `/` や `$HOME`（とその親）での起動。ホストの資格情報がまるごと rw で入ってしまうので、起動時に拒否します
- コンテナを起動するようなタスク（Docker in Docker はありません）
- ネットワークの遮断（コンテナから外部へは自由に通信できます）
- プロジェクトごとのログイン情報・会話履歴の分離（`home` ボリュームは enclaudé を使う全プロジェクトで共有されるため、あるプロジェクトで動かしたコンテナから、別プロジェクトの会話履歴やログイン情報が見えます）

## 動作環境

- Mac => OK
- Linux => 多分 OK
- Windows => 未検証

## 必要なもの

- Docker

## インストール

```shell
git clone https://github.com/kamataryo/enclaude.git
```

以下を `.zshrc`（bash なら `.bashrc`）に追記します。`/path/to/enclaude` は `git clone` したパスに読み替えてください。

```shell
export PATH="/path/to/enclaude/bin:$PATH"
eval "$(enclaudé completion)" # 補完。bash / zsh 両対応
alias enclaude=enclaudé          # é を打ちたくなければ（任意）
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
| `enclaudé resume [id]` | `enclaudé --resume [id]` と同じです |
| `enclaudé edit` | `Dockerfile.override` を `$EDITOR` で開きます。無ければ `Dockerfile.override.sample` からコピーします |
| `enclaudé rebuild` | イメージを再ビルドします。`Dockerfile` や `Dockerfile.override` を変えたとき、`git pull` で `pnpm-lock.yaml` が変わったときに実行してください |
| `enclaudé self-update` | claude-code を最新のバージョンに更新して、イメージを再ビルドします |
| `enclaudé destroy` | コンテナ・イメージ・ボリュームを削除します。ログイン状態も消えます |
| `enclaudé gh-token` | カレントディレクトリのリポジトリの Issue を読み書きするトークンを登録します |

- コンテナ自体がサンドボックスなので、`--dangerously-skip-permissions` を付けて起動します
- 初回起動時に Claude へのログインが求められます

## 守れる範囲（セキュリティ）

コンテナの中の claude は、マウントしたディレクトリを自由に書き換えられます。プロンプトインジェクションを受けた場合、その書き換えがホスト側に残るということです。**マウントしたディレクトリの中身は信用できないものとして扱ってください。**

塞いでいるのは、ホスト側で勝手に実行されるもののうち git 周りだけです。読み取り専用でマウントします。

- `.git` 全体（hooks や、config の alias / fsmonitor など、ホストで git を使った瞬間に走るもの）。config と hooks だけでは、`.git/commondir` を置いて参照先ごとすり替えられるため、丸ごと守ります
- `core.hooksPath` がワークスペースの中を指している場合（husky など）はその参照先も。husky v9 のように `.husky/_` を指す構成では、ラッパーが呼び出す親の `.husky/` ごと重ねます
- worktree / submodule の本体の gitdir。`.git` ファイルの向き先を、本体側に残っている指し返しの記録で確かめてから重ねます。無関係なリポジトリを指すよう書き換えられていたら、マウントしません

ただし多層防御の一枚であって、境界ではありません。次のものは書き換えられます。

- `package.json` の scripts、`Makefile`、`.envrc`、`.vscode/tasks.json`、`.github/workflows`、ソースコードそのもの
- `.claude/settings.json` と `.claude/settings.local.json`。ホスト側でそのディレクトリを開いて Claude Code を起動した時点で hooks が走ります
- `.mcp.json`。同じく、ホストで起動した時点で MCP サーバーの `command` が実行されます

`.claude/settings*.json` と `.mcp.json` は `git commit` より発火が早い（ホストで `claude` と打っただけで走る）ので、`.git` 周りより危険だと考えてください。

ガード自体が届かないところもあります。

- enclaudé 自身のリポジトリ。ワークスペースに含めて起動すると、コンテナの中から `bin/enclaudé` を書き換えられます。ホストの PATH に入っているので、次の起動でホスト上で実行されます（自分自身を開発できるように、あえて拒否していません）
- ワークスペースの中にネストした独立リポジトリの `.git`
- git 管理外のディレクトリ。コンテナの中から `.git` を新しく作れるので、あとでホストの git をそこで使うと、仕込まれた config や hooks が走ります
- `~/.claude.json` は読み取り専用にできないので、ユーザースコープの MCP サーバー登録は `home` ボリューム経由で以後のコンテナにも残ります
- `home` ボリュームは全プロジェクト共有なので、汚染されると以後すべてのコンテナに効き続けます
- `enclaudé gh-token` で登録したトークンは、コンテナの中から外部へ送信できます（ネットワークは遮断していません）。漏れた場合の被害は「そのリポジトリの Issue の読み書き」までです

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

イメージに入っているのは Node.js、Git、Python 3（`python3` と `uv`。pip はシステムには無いので、`python3 -m venv` か `uv` で環境を切って使います）と、基本的な CLI（`curl` / `less` / `ps` / `rg` / `jq` / `zip` / `unzip` / `file` / `gh`）だけです。PHP や Go など作業に必要なものは、`Dockerfile.override`（Git 管理外）でベースイメージの上に重ねられます。`settings.override.json` と同じく全プロジェクト共通です。

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

## GitHub の Issue を読み書きする（任意）

コンテナの中の claude に Issue を読ませたり、コメントさせたりできます。リポジトリごとに 1 回、トークンを登録してください。

```shell
cd <作業ディレクトリ>  # origin が GitHub のリポジトリ
enclaudé gh-token      # ブラウザでトークンの作成画面が開きます
enclaudé               # 以後、このリポジトリで起動したときだけ gh が使えます
```

作成画面では、名前・権限（Issues の Read and write）・有効期限（90 日）が入力済みになっています。**Repository access で「Only select repositories」を選び、対象のリポジトリだけを選んでください**（ここだけは URL で指定できません）。作成したトークンを貼り付けると、そのリポジトリにアクセスできるか確かめてから保存します。期限が切れたら、もう一度 `enclaudé gh-token` を実行してください。

- トークンはホストの `~/.config/enclaude/gh-tokens/<owner>/<repo>` に保存され、起動時に `origin` がそのリポジトリのときだけ `GH_TOKEN` としてコンテナへ渡ります。やめたいときはこのファイルを消してください
- `All repositories` は選ばないでください。無関係な private リポジトリの Issue まで漏洩の範囲に入ります
- Contents（コード）や Pull requests の権限は足さないでください。書き込み権限は、ホストで `git commit` / `push` するときに人間が見るという前提をバイパスします。とくに Contents: Write は、workflow が呼ぶスクリプトを差し替えるだけで Actions 上の任意コード実行につながります
