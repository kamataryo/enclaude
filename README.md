# enclaudé

claude-code を Docker のサンドボックスで動かすラッパー。

## 必要なもの

- Docker
- bash

## インストール

```sh
git clone git@github.com:kamataryo/enclaude.git
```

以下を `.zshrc`（bash なら `.bashrc`）に追記する。

```sh
export PATH="/path/to/enclaude/bin:$PATH"
eval "$(enclaudé completion)"          # 補完。bash / zsh 両対応
```

シェルを開き直してからイメージを用意する。

### 設定を上書きする（任意）

claude に渡す設定はリポジトリの `settings.json` に入っている。ホストの `~/.claude/settings.json` は
コンテナからは見えないので、持ち込みたい設定がある場合は `settings.override.json`（git 管理外）に書く。
起動時に `settings.json` へ重ねてマージされ、同じキーは override 側が勝つ。

```sh
pushd /path/to/enclaude
cp ~/.claude/settings.json ./settings.override.json
vi ./settings.override.json                        # 必要なパラメータだけ残す
popd
```

ホスト固有のパス（`hooks` や `env` など）はコンテナ内では壊れた参照になるので、まるごとコピーせず必要な項目だけ残すこと。

## 使い方

```shell
cd <作業ディレクトリ>
encaludé
```

| | |
|---|---|
| `enclaudé [args...]` | カレントディレクトリをマウントして起動。引数はそのまま claude に渡る |
| `enclaudé help` | enclaudé 自身のヘルプ。`--help` / `-h` は claude のヘルプ（そのまま渡る） |
| `enclaudé completion` | 補完スクリプトを出力 |
| `enclaudé destroy` | コンテナ・イメージ・ボリュームを削除（確認あり） |

※ ホストの `~/.claude/CLAUDE.md` が空の場合、自動で空のファイルを作成します

※ コンテナ自体がサンドボックスなので、`--dangerously-skip-permissions` を付けて起動します（権限確認なし）。claude-code の自動アップデートは `DISABLE_AUTOUPDATER=1` で無効化しています

### claude-code を更新する

`pnpm-lock.yaml` でバージョンを固定しているので、ロックを更新してイメージを再ビルドする。

```sh
pushd /path/to/enclaude
pnpm update --latest --lockfile-only   # 最新に上げる。範囲内で引き直すだけなら pnpm install --lockfile-only
docker-compose build
popd
```
