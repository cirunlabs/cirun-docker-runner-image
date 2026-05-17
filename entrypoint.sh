#!/usr/bin/env bash
# Container entrypoint.
#
# Decides what to do about Docker, then exec's whatever command was passed
# (cirun-agent passes `bash -lc <provision_script>`).
#
# Docker modes, in priority order:
#   1. Host socket mounted at /var/run/docker.sock
#      → use the host daemon (docker-out-of-docker). No dockerd started here.
#   2. Container has CAP_SYS_ADMIN (i.e. was started with --privileged)
#      → start dockerd in the background (docker-in-docker).
#   3. Neither — log a warning and continue. Jobs that don't touch docker
#      still work; jobs that do will see `Cannot connect to the Docker daemon`.

set -euo pipefail

log() { echo "[cirun-runner] $*" >&2; }

start_dockerd_if_possible() {
    if [[ -S /var/run/docker.sock ]]; then
        log "host docker socket detected; using docker-out-of-docker"
        return 0
    fi

    # `capsh --print` reports caps from the *bounding* set, which is full
    # inside many runtimes even when --privileged is absent. The real test
    # is whether we can actually write to the kernel — try a no-op iptables
    # rule create+delete on the nat table (what dockerd does at startup).
    # iptables-legacy is more reliable than nftables inside containers, so
    # switch first.
    update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true

    if ! iptables -t nat -N __cirun_probe >/dev/null 2>&1; then
        log "no host socket and iptables write denied; docker daemon will NOT be started"
        log "jobs that need docker will fail. Mount /var/run/docker.sock or run privileged."
        return 0
    fi
    iptables -t nat -X __cirun_probe >/dev/null 2>&1 || true

    log "starting embedded dockerd (docker-in-docker)"

    # fuse-overlayfs avoids needing the host's overlay module configured for
    # nested mounts. vfs is the safe fallback if even that fails.
    local storage_driver=fuse-overlayfs
    if ! command -v fuse-overlayfs >/dev/null 2>&1; then
        storage_driver=vfs
    fi

    dockerd \
        --host=unix:///var/run/docker.sock \
        --storage-driver="$storage_driver" \
        >/var/log/dockerd.log 2>&1 &
    local pid=$!
    echo "$pid" >/var/run/dockerd.pid

    # Wait up to 30s for the socket to appear.
    local i
    for i in $(seq 1 30); do
        if docker info >/dev/null 2>&1; then
            log "dockerd ready (pid=$pid)"
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            log "dockerd exited before becoming ready; tail of /var/log/dockerd.log:"
            tail -n 30 /var/log/dockerd.log >&2 || true
            return 0  # don't block the job — jobs that don't need docker still run
        fi
        sleep 1
    done
    log "dockerd did not become ready within 30s; continuing anyway"
}

start_dockerd_if_possible

# Hand off to the actual command (cirun-agent's provision script, or whatever
# the user passed). exec replaces the entrypoint so signals are delivered
# directly and PID 1 is the script — cirun-agent uses `pgrep -x Runner.Listener`
# to detect readiness, which works regardless of who PID 1 is.
exec "$@"
