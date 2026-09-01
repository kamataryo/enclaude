FROM node:22-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# claude-code のバージョンは pnpm-lock.yaml で固定する（dclaude self-update で更新）。
# ロックは全プラットフォームの optional 依存を持つので、Mac で生成したものをそのまま使える
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc /opt/dclaude/
RUN corepack enable \
 && cd /opt/dclaude \
 && pnpm install --frozen-lockfile \
 && ln -s /opt/dclaude/node_modules/.bin/claude /usr/local/bin/claude

# settings.json は read-only マウントにしない。claude 自身がテーマ等を書き込むため、
# イメージに焼いて named volume の初期値として渡す
COPY settings.json /home/node/.claude/settings.json
RUN chown -R node:node /home/node

USER node
WORKDIR /workspace
ENTRYPOINT ["claude"]
