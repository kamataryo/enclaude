FROM node:22-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# claude-code のバージョンは pnpm-lock.yaml で固定する（enclaudé self-update で更新）。
# ロックは全プラットフォームの optional 依存を持つので、Mac で生成したものをそのまま使える
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc /opt/enclaude/
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
