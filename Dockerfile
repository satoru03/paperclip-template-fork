# Build upstream Paperclip from a pinned ref.
FROM node:22-bookworm AS paperclip-build
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=v2026.325.0

WORKDIR /paperclip
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js

# Runtime image (direct Paperclip server, no wrapper).
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gosu \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /app
COPY --from=paperclip-build /paperclip /app

WORKDIR /wrapper
COPY package.json /wrapper/package.json
RUN npm install --omit=dev && npm cache clean --force
COPY src /wrapper/src
COPY scripts/entrypoint.sh /wrapper/entrypoint.sh
COPY scripts/bootstrap-ceo.mjs /wrapper/template/bootstrap-ceo.mjs
COPY scripts/create-invite.mjs /wrapper/scripts/create-invite.mjs
RUN chmod +x /wrapper/entrypoint.sh

# Optional local adapters/tools parity with upstream Dockerfile.
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai wrangler
RUN npm install --global --omit=dev tsx
RUN curl -fsSL https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.tar.gz -o /tmp/supabase.tar.gz \
    && tar -xzf /tmp/supabase.tar.gz -C /usr/local/bin supabase \
    && rm /tmp/supabase.tar.gz
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /paperclip /home/node/.claude \
    && chown -R node:node /app /paperclip /wrapper /home/node/.claude

# Wrap the claude binary to always pass --dangerously-skip-permissions.
# The container itself is the security boundary (isolated on Railway),
# so per-tool permission checks are unnecessary and block Paperclip agent operations.
RUN CLAUDE_BIN=$(which claude) \
    && mv "$CLAUDE_BIN" "${CLAUDE_BIN}.real" \
    && printf '#!/bin/sh\nexec "%s.real" --dangerously-skip-permissions "$@"\n' "$CLAUDE_BIN" > "$CLAUDE_BIN" \
    && chmod +x "$CLAUDE_BIN"

# Railway sets PORT at runtime and this process binds to it.
# startCommand in railway.toml calls entrypoint.sh which fixes /paperclip volume
# permissions and then execs as node via gosu.
# NOTE: Do NOT set ENTRYPOINT here — Railway's startCommand is set as CMD,
# so having both causes the entrypoint to run twice or be bypassed entirely.
EXPOSE 3100
CMD ["/wrapper/entrypoint.sh", "node", "/wrapper/src/server.js"]
