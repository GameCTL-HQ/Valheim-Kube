#!/usr/bin/env bash
# GameCTL Valheim entrypoint. The server is baked into the image at
# /opt/valheim; the volume at $CONFIG_DIR (/config) holds worlds + admin
# lists (Valheim's -savedir). Env contract matches what GameCTL's valheim
# generator has always sent (lloesche-compatible names):
#   SERVER_NAME, WORLD_NAME, SERVER_PASS (>=5 chars), SERVER_PORT,
#   SERVER_PUBLIC (1|0), SERVER_ARGS (extra flags), UID/GID.
set -euo pipefail

CFG="${CONFIG_DIR:-/config}"
uid="${UID:-1000}"; gid="${GID:-1000}"
name="${SERVER_NAME:-Valheim Server}"
world="${WORLD_NAME:-Dedicated}"
port="${SERVER_PORT:-2456}"
public="${SERVER_PUBLIC:-1}"
pass="${SERVER_PASS:-}"

if [ -n "$pass" ] && [ "${#pass}" -lt 5 ]; then
  echo "ERROR: SERVER_PASS must be at least 5 characters (Valheim requirement)" >&2
  exit 1
fi

mkdir -p "$CFG"
chown -R "$uid:$gid" "$CFG" 2>/dev/null || true

# Steam runtime wiring (what Valheim's own start_server.sh does).
export LD_LIBRARY_PATH="/opt/valheim/linux64:${LD_LIBRARY_PATH:-}"
export SteamAppId=892970

# Unity/PlayFab need a WRITABLE $HOME for the run user or the engine's logger
# segfaults during startup (BumblelionLogger in the PlayFab plugin). Point it
# at the volume so Unity state (.config/unity3d) persists too.
export HOME="$CFG"
mkdir -p "$CFG/.config"

buildid="$(grep -oE '"buildid"[^0-9]*[0-9]+' /opt/valheim/steamapps/appmanifest_896660.acf 2>/dev/null | grep -oE '[0-9]+' || echo '?')"
echo "gamectl: starting Valheim (build ${buildid}) — world '${world}' on ${port}-$((port+1))/udp, public=${public}"

run=(/opt/valheim/valheim_server.x86_64
  -nographics -batchmode
  -name "$name"
  -world "$world"
  -port "$port"
  -public "$public"
  -savedir "$CFG")
[ -n "$pass" ] && run+=(-password "$pass")
# shellcheck disable=SC2206
[ -n "${SERVER_ARGS:-}" ] && run+=(${SERVER_ARGS})

cd /opt/valheim
if [ "$(id -u)" = "0" ]; then
  exec setpriv --reuid "$uid" --regid "$gid" --clear-groups "${run[@]}"
else
  exec "${run[@]}"
fi
