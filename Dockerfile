FROM node:22-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# named volume が node 所有で初期化されるように先に作っておく
RUN mkdir -p /home/node/.claude && chown node:node /home/node/.claude

USER node
WORKDIR /workspace
ENTRYPOINT ["claude"]
