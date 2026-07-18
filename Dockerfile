# GameCTL Valheim dedicated server image — built from scratch so GameCTL
# controls exactly what runs.
#
# Sources: Debian's official base and Valve's official steamcmd tarball. The
# game (~2GB, app 896660, anonymous) installs to the persistent volume at
# /config/.gamectl/install on first boot; a normal boot NEVER runs steamcmd
# (instant restarts). Update via UPDATE_ON_START=true for one rollout —
# GameCTL's per-instance auto-update toggle drives this.
FROM debian:12-slim

RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl lib32gcc-s1 libatomic1 libpulse0 libpulse-mainloop-glib0 tini util-linux \
    && rm -rf /var/lib/apt/lists/*

# Valve's official steamcmd, primed at build (config fetched) so first-boot
# app_update can't hit the "Missing configuration" cold-start race.
RUN mkdir -p /opt/steamcmd && cd /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar xz \
    && /opt/steamcmd/steamcmd.sh +quit \
    # Real passwd entry for the run user: Unity/PlayFab calls getpwuid() during
    # startup and null-derefs (BumblelionLogger segfault) if uid 1000 has none.
    && useradd -u 1000 -d /config -M -s /usr/sbin/nologin valheim

COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

ENV CONFIG_DIR=/config \
    SERVER_NAME="Valheim Server" \
    WORLD_NAME=Dedicated \
    SERVER_PORT=2456 \
    SERVER_PUBLIC=1 \
    UPDATE_ON_START=false \
    UID=1000 \
    GID=1000

# 2456-2457/udp game+query (Valheim uses PORT and PORT+1).
EXPOSE 2456/udp 2457/udp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint"]
