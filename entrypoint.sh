#!/usr/bin/env bash
# GameCTL Valheim entrypoint. The game lives on the volume at
# $CONFIG_DIR/.gamectl/install; worlds/config at $CONFIG_DIR (-savedir) —
# lloesche-compatible layout, existing volumes migrate as-is. A normal boot
# never runs steamcmd; UPDATE_ON_START=true updates once (GameCTL toggle).
set -euo pipefail

CFG="${CONFIG_DIR:-/config}"
uid="${UID:-1000}"; gid="${GID:-1000}"
name="${SERVER_NAME:-Valheim Server}"
world="${WORLD_NAME:-Dedicated}"
port="${SERVER_PORT:-2456}"
public="${SERVER_PUBLIC:-1}"
pass="${SERVER_PASS:-}"

GAMEDIR="$CFG/.gamectl/install"
echo "gamectl: entrypoint starting (config: $CFG)"

if [ -n "$pass" ] && [ "${#pass}" -lt 5 ]; then
  echo "ERROR: SERVER_PASS must be at least 5 characters (Valheim requirement)" >&2
  exit 1
fi

mkdir -p "$GAMEDIR" "$CFG/.gamectl/steamhome"
# No recursive chown (NFS crawl); the game only writes under $CFG top-levels.
chown "$uid:$gid" "$CFG" "$CFG/.gamectl" 2>/dev/null || true
# Fix ownership of files dropped onto the share as root (e.g. an operator
# scp'ing in saves/worlds) — kubelet does not apply fsGroup to NFS volumes,
# and root-owned data files can break the server in silent ways (see
# Necesse-Kube d4b719f). Only touches mismatched files; the steamcmd install
# tree is pruned (large, root-managed, read-only for the run user).
find "$CFG" -path "$CFG/.gamectl" -prune -o ! -user "$uid" -exec chown "$uid:$gid" {} + 2>/dev/null || true

steamcmd_update() {
  for i in 1 2 3 4 5 6; do
    HOME="$CFG/.gamectl/steamhome" /opt/steamcmd/steamcmd.sh \
      +force_install_dir "$GAMEDIR" +login anonymous +app_update 896660 validate +quit && return 0
    echo "gamectl: steamcmd attempt $i failed — clearing appcache and retrying" >&2
    rm -rf "$CFG/.gamectl/steamhome/Steam/appcache" 2>/dev/null || true
    [ "$i" -ge 4 ] && { echo "gamectl: resetting steam state" >&2; rm -rf "$CFG/.gamectl/steamhome/Steam" 2>/dev/null || true; }
    sleep 10
  done
  return 1
}

need_install=0
[ -f "$GAMEDIR/valheim_server.x86_64" ] || need_install=1
if [ "$need_install" = "1" ] || [ "$(echo "${UPDATE_ON_START:-false}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  echo "gamectl: installing/updating Valheim into $GAMEDIR"
  steamcmd_update || { [ "$need_install" = "0" ] && echo "gamectl: WARN update failed, starting existing install" || { echo "ERROR: install failed" >&2; exit 1; }; }
else
  echo "gamectl: existing install found — starting without steamcmd (set UPDATE_ON_START=true to update)"
fi

# Steam runtime wiring (what Valheim's own start_server.sh does).
export LD_LIBRARY_PATH="$GAMEDIR/linux64:${LD_LIBRARY_PATH:-}"
export SteamAppId=892970
# Unity/PlayFab need a WRITABLE $HOME for the run user (segfault otherwise);
# pointing it at the volume also persists Unity state.
export HOME="$CFG"

buildid="$(grep -oE '"buildid"[^0-9]*[0-9]+' "$GAMEDIR/steamapps/appmanifest_896660.acf" 2>/dev/null | grep -oE '[0-9]+' || echo '?')"
echo "gamectl: starting Valheim (build ${buildid}) — world '${world}' on ${port}-$((port+1))/udp, public=${public}"

run=("$GAMEDIR/valheim_server.x86_64"
  -nographics -batchmode
  -name "$name"
  -world "$world"
  -port "$port"
  -public "$public"
  -savedir "$CFG")
[ -n "$pass" ] && run+=(-password "$pass")
# shellcheck disable=SC2206
[ -n "${SERVER_ARGS:-}" ] && run+=(${SERVER_ARGS})

cd "$GAMEDIR"
if [ "$(id -u)" = "0" ]; then
  exec setpriv --reuid "$uid" --regid "$gid" --clear-groups "${run[@]}"
else
  exec "${run[@]}"
fi
