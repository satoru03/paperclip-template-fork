#!/bin/sh
set -e
# When Railway mounts a volume at /paperclip it is often not writable by the node user.
# Create dirs Paperclip needs and ensure the whole tree is owned by node.
mkdir -p /paperclip/instances/default/logs
chown -R node:node /paperclip

# --- One-time full purge (remove this block after successful deploy) ---
# All persistent data is in PostgreSQL; /paperclip volume only has logs,
# workspaces, and caches that Paperclip will recreate automatically.
PURGE_MARKER="/paperclip/.purged-v1"
if [ ! -f "$PURGE_MARKER" ]; then
  echo "[entrypoint] One-time full purge of /paperclip volume..."
  echo "[entrypoint] Before purge: $(du -sh /paperclip 2>/dev/null | cut -f1)"
  find /paperclip -mindepth 1 -not -name ".purged-v1" -delete 2>/dev/null || true
  mkdir -p /paperclip/instances/default/logs
  touch "$PURGE_MARKER"
  echo "[entrypoint] After purge: $(du -sh /paperclip 2>/dev/null | cut -f1)"
fi

# Ongoing cleanup: remove files older than N days to prevent ENOSPC.
LOG_CLEANUP_DAYS="${LOG_CLEANUP_DAYS:-3}"
echo "[entrypoint] Routine cleanup (>${LOG_CLEANUP_DAYS} days old)..."
echo "[entrypoint] Before cleanup: $(du -sh /paperclip 2>/dev/null | cut -f1)"
find /paperclip -type f \( -name "*.log" -o -name "*.jsonl" -o -name "*.ndjson" \) -mtime +"${LOG_CLEANUP_DAYS}" -delete 2>/dev/null || true
find /home/node/.claude -type f -mtime +"${LOG_CLEANUP_DAYS}" -delete 2>/dev/null || true
find /paperclip/instances -maxdepth 5 -type d -name "node_modules" -mtime +"${LOG_CLEANUP_DAYS}" -exec rm -rf {} + 2>/dev/null || true
find /paperclip/instances -maxdepth 6 -type d -name ".git" -mtime +"${LOG_CLEANUP_DAYS}" -exec rm -rf {} + 2>/dev/null || true
find /paperclip/instances -type d -empty -delete 2>/dev/null || true
echo "[entrypoint] After cleanup: $(du -sh /paperclip 2>/dev/null | cut -f1)"

# Pre-authenticate Claude Code if ANTHROPIC_API_KEY is set.
# This runs a quick print-mode call to establish auth session files
# before Paperclip starts its probe.
if [ -n "$ANTHROPIC_API_KEY" ]; then
  echo "[entrypoint] Pre-authenticating Claude Code..."
  if gosu node claude -p "ok" --bare --max-turns 1 > /dev/null 2>&1; then
    echo "[entrypoint] Claude Code auth OK"
  else
    echo "[entrypoint] Claude Code pre-auth failed (will retry at runtime)"
  fi
fi

exec gosu node "$@"
