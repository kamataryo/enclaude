#!/bin/sh
# compose が渡す settings.json と settings.override.json をマージしてから claude を起動する。
set -e

node /opt/enclaude/merge-settings.mjs /mnt/settings.json /mnt/settings.override.json \
  > /tmp/enclaude-settings.json

# コンテナ自体がサンドボックスなので、権限確認はスキップして起動する
exec claude --settings /tmp/enclaude-settings.json --dangerously-skip-permissions "$@"
