#!/bin/sh
set -e
# When Railway mounts a volume at /paperclip it is often not writable by the node user.
# Create dirs Paperclip needs and ensure the whole tree is owned by node.
mkdir -p /paperclip/instances/default/logs
chown -R node:node /paperclip

# Clean up old run logs to prevent ENOSPC.
# Removes log files older than 7 days under the Paperclip data directory.
LOG_CLEANUP_DAYS="${LOG_CLEANUP_DAYS:-7}"
echo "[entrypoint] Cleaning up log files older than ${LOG_CLEANUP_DAYS} days..."
find /paperclip -type f \( -name "*.log" -o -name "*.jsonl" \) -mtime +"${LOG_CLEANUP_DAYS}" -delete 2>/dev/null || true
# Also remove empty directories left behind.
find /paperclip/instances/default/logs -type d -empty -delete 2>/dev/null || true
echo "[entrypoint] Disk usage: $(du -sh /paperclip 2>/dev/null | cut -f1)"

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
