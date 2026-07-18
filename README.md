# Valheim-Kube

A from-scratch **Valheim dedicated server** image for Kubernetes, maintained by
[GameCTL](https://github.com/GameCTL-HQ/GameCTL) so nothing changes underneath us.

Sources in the chain: Debian's official base, **Valve's official steamcmd**, and
the Valheim server from **Steam's CDN** (app `896660`, anonymous — no login).
No community images.

**The server is baked at build time, not downloaded at boot** — pods start in
seconds, first boot can't flake on Steam CDN weather, and the tag pins the exact
Steam build. A daily GitHub Action rebuilds only when Valve ships a new build.

## Image

`ghcr.io/gamectl-hq/valheim-kube`

- `:latest` — newest server build
- `:build-<steam buildid>` — pinned, reproducible

## Usage

```bash
docker run -d --name valheim \
  -p 2456-2457:2456-2457/udp \
  -v /srv/valheim:/config \
  -e SERVER_NAME="My Server" -e WORLD_NAME=Midgard \
  -e SERVER_PASS=secret123 -e SERVER_PUBLIC=0 \
  ghcr.io/gamectl-hq/valheim-kube:latest
```

The volume at `/config` is Valheim's `-savedir` (worlds at
`/config/worlds_local/`, admin/ban/permitted lists alongside) — the same layout
as lloesche-based setups, so existing volumes migrate as-is.

### Environment (lloesche-compatible names)

| Var | Default | Notes |
|-----|---------|-------|
| `SERVER_NAME` | `Valheim Server` | Listing name |
| `WORLD_NAME` | `Dedicated` | World (db/fwl) name |
| `SERVER_PASS` | — | Min 5 chars (Valheim requirement); empty = no password |
| `SERVER_PORT` | `2456` | Uses PORT and PORT+1 (UDP) |
| `SERVER_PUBLIC` | `1` | `0` = hidden from the server list |
| `SERVER_ARGS` | — | Extra flags appended to the server command |
| `UID` / `GID` | `1000` | Server runs unprivileged |

## Ports

`2456/udp` + `2457/udp` (game + query).
