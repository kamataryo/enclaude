# Claude Code enclavé, c'est *Enclaudé*.

Claude Code を Docker のサンドボックスで動かすラッパーです。

## 必要なもの

- Docker
- bash

## インストール

```shell
git clone git@github.com:kamataryo/enclaude.git
```

以下を `.zshrc`（bash なら `.bashrc`）に追記します。`/path/to/enclode` は git clone したパスに読み替えてください。

```shell
export PATH="/path/to/enclaude/bin:$PATH"
eval "$(enclaudé completion)" # 補完。bash / zsh 両対応
```

### Claude の設定を上書きする（任意）

claude に渡す設定はリポジトリの `settings.json` に入っています。ホストの `~/.claude/settings.json` はコンテナからはみない設定なので、持ち込みたい設定がある場合は `settings.override.json`（git 管理外）に書いてください。
起動時に `settings.json` へ重ねてマージされ、同じキーは override 側が勝ちます。

```shell
pushd /path/to/enclaude
cp ~/.claude/settings.json ./settings.override.json
vi ./settings.override.json # 必要なパラメータだけ残す
popd
```

ホスト固有のパス（`hooks` や `env` など）はコンテナ内では壊れた参照になるので、まるごとコピーせず必要な項目だけ残してください。

## 使い方

```shell
cd <作業ディレクトリ>
enclaudé
```

| コマンド| 適用 |
|---|---|
| `enclaudé [args...]` | カレントディレクトリをマウントして起動します。引数はそのまま claude に渡ります |
| `enclaudé help` | enclaudé 自身のヘルプです。`--help` / `-h` は claude のヘルプ（そのまま渡ります） |
| `enclaudé completion` | 補完スクリプトを出力します |
| `enclaudé destroy` | コンテナ・イメージ・ボリュームを削除します（確認あり） |

- ホストの `~/.claude/CLAUDE.md` が空の場合、自動で空のファイルを作成します
- コンテナ自体がサンドボックスなので、`--dangerously-skip-permissions` を付けて起動します
- 初回起動時に Claude へのログインが求められます
- claude-code の自動アップデートは `DISABLE_AUTOUPDATER=1` で無効化しています。アップデートしたい場合は、以下の手順でアップデートしてください

### claude-code を更新する

`pnpm-lock.yaml` でバージョンを固定しているので、ロックを更新してイメージを再ビルドします。

```sh
pushd /path/to/enclaude
pnpm update --latest --lockfile-only   # 最新に上げる。範囲内で引き直すだけなら pnpm install --lockfile-only
docker compose build
popd
```
