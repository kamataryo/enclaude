#!/bin/sh
# ホストの settings.json を起動のたびに反映する。
# 単一ファイルを直接 bind mount すると claude の atomic write（tmp + rename）が
# "Device or resource busy" で失敗するため、ro で渡してコピーする。
# 丸ごと上書きすると claude 自身が書いた theme などが毎回消えるので、ホスト側を優先してマージする。
[ -f /mnt/settings.json ] && node -e '
  const fs = require("fs"), p = process.env.HOME + "/.claude/settings.json";
  const cur = fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : {};
  const host = JSON.parse(fs.readFileSync("/mnt/settings.json", "utf8"));
  fs.writeFileSync(p, JSON.stringify({ ...cur, ...host }, null, 2));
'
exec claude "$@"
