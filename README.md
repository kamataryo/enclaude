# dclaude

claude-code を Docker のサンドボックスで動かす最小構成。

## 使い方

```sh
docker-compose build

# 初回のみ: コンテナ内でログイン（ブラウザ認証）
WORKSPACE=~/path/to/project docker-compose run --rm claude

# 2回目以降。隔離されているので権限確認をスキップして使える
WORKSPACE=~/path/to/project docker-compose run --rm claude --dangerously-skip-permissions
```

`WORKSPACE` 省略時は `./workspace` がマウントされる。

シェルに入りたいとき:

```sh
docker-compose run --rm --entrypoint bash claude
```

## 構成

| | |
|---|---|
| ベース | `node:22-slim` + git |
| 実行ユーザー | `node`（root だと `--dangerously-skip-permissions` が使えない） |
| 認証 | named volume `claude-home` に永続化。ホストの Keychain は使えないのでコンテナ内で `/login` |
| 設定 | ホストの `~/.claude/CLAUDE.md` を read-only、`settings.json` はコンテナ用の最小版 |
| 隔離範囲 | `WORKSPACE` に指定したディレクトリのみホストに書き込まれる。それ以外のホストは触れない |

ホストの `~/.claude/settings.json` はマウントしていない。`statusLine` がホスト絶対パスを参照し、`sandbox.enabled` がコンテナ内で二重サンドボックスになるため。

## やっていないこと

- ネットワーク制限なし。`npm install` も WebFetch も素通り
- 会話履歴・plugins はホストと共有しない
- `WORKSPACE` 配下はホスト実体なので、そこだけは保護されない
