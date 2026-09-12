# タグだけでなくダイジェストで固定する。node:22-slim は 22-slim のまま中身が入れ替わるため、
# タグ指定だけだと再ビルドのたびに異なるイメージを引く可能性がある。更新するときは
# `docker manifest inspect node:22-slim` 等で最新のダイジェストを確認して書き換える
FROM node:22-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5

# slim には git / curl / less / ps / rg が無い。ripgrep は claude の Grep が使う（無いと grep に
# フォールバックして遅くノイズも多い）。less は git のページャ、procps は ps、curl は疎通確認用。
# python3 は Debian 12 の 3.11。PEP 668 でシステムへの pip install は拒否されるので、
# パッケージは python3-venv で venv を切るか、下の uv で入れる
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates curl less procps ripgrep jq unzip zip file \
      python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

# uv は公式イメージから静的バイナリだけ持ってくる（curl | sh より固定しやすい）。
# ベースと同じくダイジェストで固定する。更新するときはバージョンを書き換えたうえで
# `docker manifest inspect astral/uv:<version>` のダイジェスト（amd64 / arm64 を含む index のもの）に差し替える。
# キャッシュや uv が入れる Python は ~/.cache/uv と ~/.local/share/uv に置かれ、home ボリュームで永続化される
COPY --from=docker.io/astral/uv:0.12.13@sha256:b485bd65cc2cf1c9a93b3554012c9c3778cf7b1b5fd3d3096ce9e1226c97e1e6 /uv /uvx /usr/local/bin/

# claude-code のバージョンは pnpm-lock.yaml で固定する（enclaudé self-update で更新）。
# ロックは全プラットフォームの optional 依存を持つので、Mac で生成したものをそのまま使える
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml /opt/enclaude/
RUN corepack enable \
 && cd /opt/enclaude \
 && pnpm install --frozen-lockfile \
 && ln -s /opt/enclaude/node_modules/.bin/claude /usr/local/bin/claude

RUN mkdir -p /home/node/.claude && chown -R node:node /home/node

# compose が ./settings.json と ./settings.override.json を ro で渡す。claude はこれらに
# 書き込まないので bind mount のままでよく、entrypoint がマージした結果を --settings に渡す
COPY entrypoint.sh merge-settings.mjs /opt/enclaude/
RUN chmod +x /opt/enclaude/entrypoint.sh

USER node
WORKDIR /workspace
ENTRYPOINT ["/opt/enclaude/entrypoint.sh"]
