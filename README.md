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

### claude-code を更新する

`pnpm-lock.yaml` でバージョンを固定しているので、ロックを更新してイメージを再ビルドする。

```sh
pushd /path/to/enclaude
pnpm update --latest --lockfile-only   # 最新に上げる。範囲内で引き直すだけなら pnpm install --lockfile-only
docker-compose build
popd
```
