# syntax=docker/dockerfile:1.7
#
# cirun-docker-runner-image — Ubuntu 24.04 base with everything a GitHub Actions
# self-hosted runner needs to bootstrap, plus an embedded Docker daemon for
# jobs that need `docker build` / `docker run` inside the runner.
#
# Three modes are auto-selected at container start (see entrypoint.sh):
#   1. Host socket mounted at /var/run/docker.sock  → "docker-out-of-docker"
#   2. Container is --privileged                    → "docker-in-docker"
#   3. Neither                                      → no docker; non-docker
#                                                     jobs still run
#
# Two image variants share this Dockerfile via BASE_IMAGE:
#   - base: ubuntu:24.04                              (tag: latest, 24.04)
#   - gpu:  nvidia/cuda:13.2.1-base-ubuntu24.04       (tag: gpu, gpu-cuda13.2)
# The GPU variant adds CUDA libs + nvidia-container-toolkit hooks via the
# nvidia/cuda base; the rest of the layers are identical.

ARG BASE_IMAGE=ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RUNNER_ALLOW_RUNASROOT=1 \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache

# ── Base packages ─────────────────────────────────────────────────────────
# - actions/runner deps:    libicu, libssl, zlib, krb5, ca-certificates
# - typical CI deps:        git, curl, wget, jq, unzip, xz-utils, build-essential,
#                           python3, openssh-client, gnupg, lsb-release
# - DinD plumbing:          iptables, iproute2, kmod, fuse-overlayfs, uidmap,
#                           pigz, e2fsprogs, xfsprogs
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg lsb-release sudo locales tzdata \
      git openssh-client \
      libicu74 libssl3 libkrb5-3 zlib1g \
      jq unzip xz-utils tar gzip pigz \
      build-essential python3 python3-pip python3-venv \
      iptables iproute2 kmod fuse-overlayfs uidmap libcap2-bin \
      e2fsprogs xfsprogs \
    && rm -rf /var/lib/apt/lists/*

# ── Docker engine + CLI + compose plugin ──────────────────────────────────
# Installed from Docker's official apt repo. The daemon stays off until the
# entrypoint decides whether to start it. Pinned major version range; bump
# the apt key + repo URL together if Docker changes signing.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ── GitHub Actions runner pre-stage (optional) ────────────────────────────
# We deliberately do NOT bake the runner binary into the image. Cirun's
# provision_script downloads the exact version the SaaS expects and runs
# `config.sh` / `run.sh`. Keeping it out of the image avoids version skew
# and shrinks the image.
#
# We pre-create the directory + cache path so the script doesn't have to.
RUN mkdir -p /actions-runner /opt/hostedtoolcache \
    && chmod 0777 /opt/hostedtoolcache

# ── Entrypoint ────────────────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /actions-runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Default to an interactive shell when the image is run without a command.
# Cirun-agent overrides this with `bash -lc <provision_script>`.
CMD ["bash"]
