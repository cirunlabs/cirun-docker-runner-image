# cirun-docker-runner-image

Docker runner image for [cirun-agent](https://github.com/cirunlabs/cirun-agent)
self-hosted runners.

Ubuntu 24.04 base with everything a GitHub Actions runner needs to bootstrap,
plus an embedded Docker daemon so jobs can run `docker build`, `docker run`,
`docker compose`, etc.

## Usage

In `.cirun.yml`:

```yml
runners:
  - name: cirun-docker-runner
    cloud: on_prem
    instance_type: 4vcpu-8gb
    machine_image: "ghcr.io/cirunlabs/cirun-docker-runner-image:latest"
    region: RegionOne
    labels:
      - cirun-docker-runner
    extra_config:
      executor: docker
```

## Docker access inside jobs

The entrypoint auto-selects one of three modes at container start:

| Condition                                                     | Mode                       | Docker available? |
|---------------------------------------------------------------|----------------------------|-------------------|
| `/var/run/docker.sock` is mounted from the host               | docker-out-of-docker       | yes (host daemon) |
| Container is `--privileged` (cgroup + iptables capabilities)  | docker-in-docker (`dockerd` started inside) | yes (isolated)    |
| Neither                                                       | runner-only                | no — docker-touching jobs fail |

Cirun-agent does not currently pass `--privileged` or mount the host
socket. Until that's wired through `.cirun.yml`, the image runs in
**runner-only** mode on the SaaS path; you get docker access by running
the image manually with one of the two flags above (useful for local
testing and for self-managed dispatch).

### Local test

```bash
# DinD
docker run --rm --privileged ghcr.io/cirunlabs/cirun-docker-runner-image:latest \
    bash -lc 'docker run --rm hello-world'

# Socket mount
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    ghcr.io/cirunlabs/cirun-docker-runner-image:latest \
    bash -lc 'docker run --rm hello-world'
```

## What's in the image

- Ubuntu 24.04
- GitHub Actions runner dependencies (`libicu74`, `libssl3`, `libkrb5-3`, `zlib1g`)
- Common CI tooling: `git`, `curl`, `wget`, `jq`, `unzip`, `xz-utils`,
  `build-essential`, `python3` + `pip` + `venv`, `openssh-client`
- Docker Engine + CLI + `buildx` + `compose` plugins
- DinD support: `iptables`, `iproute2`, `fuse-overlayfs`, `libcap2-bin`
- `/opt/hostedtoolcache` pre-created for `actions/setup-*` actions

The GitHub Actions runner binary itself is **not** baked in — cirun's
provision script downloads the version the SaaS expects at job start, which
avoids version skew between the image and the platform.

## Building locally

```bash
docker build -t cirun-docker-runner:dev .
```

## Variants

`latest` and `24.04` track Ubuntu 24.04. The image is built for `linux/amd64`
and `linux/arm64`.

## License

MIT — see [LICENSE](LICENSE).
