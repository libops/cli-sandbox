# cli-sandbox

Run `claude`, `codex`, or `pi` in a docker container.

The image defaults to the managed Task Agent egress profile. That profile allows
one operator-configured model gateway IPv4/TCP tuple, blocks runtime DNS, and
drops all IPv6 traffic. Broader direct-provider access is available only through
an explicit interactive profile that is not a confidentiality boundary.

## Requirements

- docker
  - With Docker's default capability set, pass
    `--cap-add=NET_ADMIN --cap-add=NET_RAW` so the image can configure the
    firewall.
  - If you also use `--cap-drop=ALL`, add back exactly `NET_ADMIN`, `NET_RAW`,
    `SETGID`, and `SETUID`. The container starts as `node`; the latter two are
    required only for the constrained `sudo` transition that runs firewall
    bootstrap. The sudo rule is revoked before the requested CLI starts, and
    the CLI remains an unprivileged process with no effective, permitted, or
    ambient capabilities.
- Managed runs must provide `TASK_AGENT_MODEL_BASE_URL` with the literal IPv4
  address provisioned for the project's model-gateway Private Service Connect
  endpoint.
- You will need to mount the codebase you want to work on inside the container
- To persist your auth and settings for gemini and claude, you'll want to mount those directories into `/home/node` (see usage below)

## Usage

```bash
CODE_CLI=claude
cd /path/to/codebase
docker run \
  -v $HOME/.$CODE_CLI:/home/node/.$CODE_CLI \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -e CLI_SANDBOX_EGRESS_PROFILE=interactive \
  -v ./:/workspace \
  -w /workspace \
  --rm -it \
  ghcr.io/libops/cli-sandbox:main \
  "$CODE_CLI"
# chit chat
```

### Task Agent model gateway

`managed` is the default profile. It requires `TASK_AGENT_MODEL_BASE_URL` and
accepts only a literal IPv4 authority, matching the per-project Private Service
Connect address provisioned by the LibOps platform:

```bash
docker run \
  --cap-drop=ALL \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --cap-add=SETGID \
  --cap-add=SETUID \
  -e TASK_AGENT_MODEL_BASE_URL=http://10.42.17.9/v1 \
  -v ./:/workspace \
  -w /workspace \
  --rm -it \
  ghcr.io/libops/cli-sandbox:codex \
  codex
```

The managed firewall accepts lowercase `http://` or `https://` URLs without
userinfo, query strings, fragments, whitespace, backslashes, DNS names, or IPv6
authorities. Unspecified, loopback, link-local—including the cloud metadata
range—multicast, and reserved broadcast destinations are rejected. The only
runtime egress allowance is TCP to that exact `/32` and the URL's explicit port,
or port 80/443 according to its scheme. Runtime UDP/TCP DNS is rejected,
Docker's embedded DNS rules are not restored, and the IPv6 INPUT, FORWARD, and
OUTPUT policies are `DROP`. Invalid configuration stops the container before
the coding CLI starts.

The URL is an operator-controlled trust input, not a task-controlled option.

For managed LibOps Task Agent runs, the runtime controller creates and mounts a
fresh `CODEX_HOME` containing the reviewed, content-addressed site-change and
application-family skill bundle. This image intentionally does not fetch or
own mutable skill source. The controller also omits Git/forge/cloud credentials,
the host home, production checkouts, and the Docker socket; those boundaries
must not be relaxed by a task or skill.

Managed tasks cannot contact GitHub, package registries, or direct AI-provider
endpoints. The runtime controller must materialize the reviewed checkout and
dependencies before launch, then collect the resulting patch for an
out-of-container Git/PR workflow. This keeps forge credentials and the network
authority to publish changes outside the untrusted coding process.

### Interactive egress profile

For a trusted human-driven session that needs the historical GitHub and direct
AI-provider behavior, opt in explicitly:

```bash
-e CLI_SANDBOX_EGRESS_PROFILE=interactive
```

Interactive mode restores live DNS and the broader provider-published network
allowlists. Shared service networks and DNS can carry arbitrary data, so this
profile must not be used for managed or otherwise untrusted Task Agent runs.
DNS model-gateway hostnames and `CLI_SANDBOX_ALLOW_HOST_NETWORK=true` are
accepted only in this profile.

`SKIP_EGRESS_FIREWALL=true` is likewise accepted only with the interactive
profile and disables the firewall entirely. It is intended solely for trusted
local diagnostics.

### Docker host network access

The firewall does not allow the Docker host subnet by default. Unix-domain
socket access, including `/var/run/docker.sock`, does not need an IP firewall
exception. If a trusted workload must reach TCP or UDP services bound to the
Docker host network, an operator can explicitly restore the legacy `/24`
allowance with:

```bash
-e CLI_SANDBOX_EGRESS_PROFILE=interactive
-e CLI_SANDBOX_ALLOW_HOST_NETWORK=true
```

Only the exact lowercase value `true` enables the INPUT and OUTPUT rules;
`false` or an unset variable keeps them disabled, and any other value stops
startup. Managed mode rejects `true` even when it is explicitly supplied. This
option exposes every service reachable on the detected host
gateway's `/24`, so do not enable it for untrusted coding tasks. Prefer a
narrow destination-specific exception when one is available.

### Using Docker inside the sandbox

The image ships the Docker CLI, so you can drive the host's Docker daemon from
inside the sandbox by bind-mounting the daemon socket.

This interactive convenience is never part of the managed Task Agent runtime.

The container runs as the unprivileged `node` user, and access to
`/var/run/docker.sock` is controlled by the **group** that owns it on the host.
That group's numeric GID varies by host and rarely matches any group inside the
image, so grant it explicitly at launch with `--group-add`:

```bash
docker run \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -e CLI_SANDBOX_EGRESS_PROFILE=interactive \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --group-add "$(stat -c %g /var/run/docker.sock)" \
  -v ./:/workspace \
  -w /workspace \
  --rm -it \
  ghcr.io/libops/cli-sandbox:main \
  claude
```

`--group-add` adds the socket's GID to `node`'s supplementary groups at
container start, so `docker ps` works immediately — no entrypoint changes and
no editing the socket (which is typically mounted read-only). Inside the
container, verify with `docker ps`.

Notes:

- This grants the container full control of the host Docker daemon, which is
  effectively root on the host. Only do this for trusted workloads.
- `stat -c %g` is Linux. On Docker Desktop (macOS/Windows) the socket GID
  differs; check it with `ls -ln /var/run/docker.sock` and pass that number, or
  use `group_add` in a compose file.

### alias

With the following in your shell's dot file, you can

```
cd path/to/code
gemini
```

And you’ll get dropped into a sandbox’d docker container with the respective CLI with firewall protection and no host filesystem access besides the claude/gemini settings dir and the codebase mounted into the container. Be sure to uninstall claude or gemini from your machine to avoid conflicts.

```bash
ccli() {
  if [ "$#" != 1 ]; then
    echo "Need to pass gemini or claude"
    return
  fi

  local cli=$1
  if [ "$cli" != "codex" ] && [ "$cli" != "claude" ] && [ "$cli" != "pi" ]; then
    echo "Need to pass claude, codex, or pi"
    return
  fi

  if [ "$(pwd)" = "$HOME" ]; then
    echo "You should cd into your codebase"
    echo "Running this command here would mount your entire home directory into $cli"
    return
  fi

  local git_name=$(git config --global user.name)
  local git_email=$(git config --global user.email)

  docker run \
    -v $HOME/.$cli:/home/node/.$cli \
    --cap-add=NET_ADMIN --cap-add=NET_RAW \
    -e CLI_SANDBOX_EGRESS_PROFILE=interactive \
    -e COLUMNS=$(tput cols) \
    -e LINES=$(tput lines) \
    -e GIT_AUTHOR_NAME="$git_name" \
    -e GIT_AUTHOR_EMAIL="$git_email" \
    -e GIT_COMMITTER_NAME="$git_name" \
    -e GIT_COMMITTER_EMAIL="$git_email" \
    -v ./:/workspace \
    -w /workspace \
    --rm -it \
    ghcr.io/libops/cli-sandbox:main \
    "$cli"
}

claude() {
  ccli claude
}

codex() {
  ccli codex
}

pi() {
  ccli pi
}
```

## Attribution

- `Dockerfile` and `init-firewall.sh` forked from [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/.devcontainer). Added Gemini support, installed Go, and retained the original Google provider ranges only in the explicit interactive profile.
- `download.sh` copied from [islandora-devops/isle-buildkit](https://github.com/Islandora-Devops/isle-buildkit/tree/main/base/rootfs/usr/local/bin)

## Tests

Run the parser and rule tests directly:

```bash
bash tests/init-firewall_test.sh
```

The runtime contract is an image-level test. It verifies the managed gateway
tuple, absence of runtime DNS and broad provider sets, IPv6 drop policies,
post-bootstrap capability removal, sudo revocation, and explicit interactive
profile startup. For an existing image, overlay the current checked-in programs
in a small fixture image and run:

```bash
docker build \
  --build-arg BASE_IMAGE=ghcr.io/libops/cli-sandbox:codex \
  -f tests/Dockerfile.runtime-capabilities \
  -t cli-sandbox:runtime-capabilities-test .
bash tests/runtime-capabilities_test.sh cli-sandbox:runtime-capabilities-test
```
