# GameCTL Valheim dedicated server image — built from scratch so GameCTL
# controls exactly what runs.
#
# Sources: Debian's official base, Valve's official steamcmd tarball, and the
# Valheim dedicated server from Steam's CDN (app 896660, anonymous — no login).
#
# The server is baked at BUILD time (multi-stage), not downloaded at boot:
# pods start fast, first boot can't flake on Steam CDN, and the image tag pins
# the exact server build. CI rebuilds weekly to track updates.
FROM debian:12-slim AS steam

RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl lib32gcc-s1 \
    && rm -rf /var/lib/apt/lists/*

# Valve's official steamcmd (not a community image).
RUN mkdir -p /steamcmd && cd /steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar xz

# Bust the layer cache when a new server build exists (CI passes the live
# build id); harmless default for local builds.
ARG VALHEIM_BUILDID=dev
RUN echo "target buildid: ${VALHEIM_BUILDID}" \
    && for i in 1 2 3 4 5; do \
         /steamcmd/steamcmd.sh +force_install_dir /opt/valheim +login anonymous +app_update 896660 validate +quit && break \
         || { echo "steamcmd attempt $i failed (cold-start config race); sleep + retry"; sleep 10; }; \
       done \
    && test -f /opt/valheim/steamapps/appmanifest_896660.acf \
    && grep -E '"buildid"' /opt/valheim/steamapps/appmanifest_896660.acf


FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libatomic1 libpulse0 libpulse-mainloop-glib0 tini util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY --from=steam /opt/valheim /opt/valheim
COPY entrypoint.sh /usr/local/bin/entrypoint
# Real passwd entry for the run user: Unity/PlayFab calls getpwuid() during
# startup and null-derefs (BumblelionLogger segfault) if uid 1000 has none.
RUN useradd -u 1000 -d /config -M -s /usr/sbin/nologin valheim \
    && chmod +x /usr/local/bin/entrypoint

ENV CONFIG_DIR=/config \
    SERVER_NAME="Valheim Server" \
    WORLD_NAME=Dedicated \
    SERVER_PORT=2456 \
    SERVER_PUBLIC=1 \
    UID=1000 \
    GID=1000

# 2456-2457/udp game+query (Valheim uses PORT and PORT+1).
EXPOSE 2456/udp 2457/udp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
