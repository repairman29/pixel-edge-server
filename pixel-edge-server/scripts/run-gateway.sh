#!/data/data/com.termux/files/usr/bin/bash
# Run the gateway with env loaded.
[ -f ~/.env.pixel-agent ] && . ~/.env.pixel-agent
BIN=""
for p in "$HOME/pixel-agent-v2" "$HOME/pixel-agent-v2-src/target/release/pixel-agent-v2"; do
  [ -x "$p" ] && BIN="$p" && break
done
if [ -z "$BIN" ]; then
  echo "Binary not found. Run the build first: bash /sdcard/jarvis/build-in-termux.sh"
  exit 1
fi
exec "$BIN" "$@"
