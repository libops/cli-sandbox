# cli-sandbox

Run `claude`, `codex`, `gemini`, `opencode`, or `pi` in a docker container.

`iptables` is used inside the container to block all outbound traffic except the
reviewed GitHub/AI service allowlists and, when explicitly configured, the exact
Task Agent model gateway destination.

## Requirements

- docker
  - With Docker's default capability set, pass
    `--cap-add=NET_ADMIN --cap-add=NET_RAW` so the image can configure the
    firewall.
  - If you also use `--cap-drop=ALL`, add back exactly `NET_ADMIN`, `NET_RAW`,
    `SETGID`, and `SETUID`. The container starts as `node`; the latter two are
    required only for the constrained `sudo` transition that runs firewall
    bootstrap. The sudo rule is revoked before the requested CLI starts, and
    the CLI remains an unprivileged process with no effective capabilities.
- You will need to mount the codebase you want to work on inside the container
- To persist your auth and settings for gemini and claude, you'll want to mount those directories into `/home/node` (see usage below)

## Usage

```bash
CODE_CLI=claude
cd /path/to/codebase
docker run \
  -v $HOME/.$CODE_CLI:/home/node/.$CODE_CLI \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -v ./:/workspace \
  -w /workspace \
  --rm -it \
  ghcr.io/libops/cli-sandbox:main \
  "$CODE_CLI"
# chit chat
```

### Task Agent model gateway

Set `TASK_AGENT_MODEL_BASE_URL` when the coding CLI must call a model gateway
that is not already in the static egress allowlist. For a Private Service
Connect endpoint:

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

The firewall accepts only lowercase `http://` or `https://` URLs without
userinfo, query strings, fragments, whitespace, backslashes, or IPv6
authorities. A literal IPv4 address is added as one exact `/32` destination.
A valid DNS hostname is resolved once during startup and each returned IPv4
address is added individually (up to 32 addresses). Unspecified, loopback,
link-local—including the cloud metadata range—multicast, and reserved broadcast
destinations are rejected. The egress rule is limited to TCP and the URL's
explicit port, or port 80/443 according to its scheme; it is installed before
the general Google customer-address rejection so a private PSC address works.
Invalid configuration stops the container before the coding CLI starts.

The URL is an operator-controlled trust input, not a task-controlled option.
Restart the container when a DNS-backed gateway changes addresses.

For managed LibOps Task Agent runs, the runtime controller creates and mounts a
fresh `CODEX_HOME` containing the reviewed, content-addressed site-change and
application-family skill bundle. This image intentionally does not fetch or
own mutable skill source. The controller also omits Git/forge/cloud credentials,
the host home, production checkouts, and the Docker socket; those boundaries
must not be relaxed by a task or skill.

### Docker host network access

The firewall does not allow the Docker host subnet by default. Unix-domain
socket access, including `/var/run/docker.sock`, does not need an IP firewall
exception. If a trusted workload must reach TCP or UDP services bound to the
Docker host network, an operator can explicitly restore the legacy `/24`
allowance with:

```bash
-e CLI_SANDBOX_ALLOW_HOST_NETWORK=true
```

Only the exact lowercase value `true` enables the INPUT and OUTPUT rules;
`false` or an unset variable keeps them disabled, and any other value stops
startup. This option exposes every service reachable on the detected host
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
  if [ "$cli" != "opencode" ] && [ "$cli" != "codex" ] && [ "$cli" != "claude" ] && [ "$cli" != "gemini" ]; then
    echo "Need to pass opencode, codex, gemini, or claude"
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

gemini() {
  ccli gemini
}

claude() {
  ccli claude
}

codex() {
  ccli codex
}

opencode() {
  ccli opencode
}
```

## Attribution

- `Dockerfile` and `init-firewall.sh` forked from [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/.devcontainer). Added gemini support and installed `go`. Also changed the firewall to allow access to google internal IPs
- `download.sh` copied from [islandora-devops/isle-buildkit](https://github.com/Islandora-Devops/isle-buildkit/tree/main/base/rootfs/usr/local/bin)

## Tests

Run the parser and rule tests directly:

```bash
bash tests/init-firewall_test.sh
```

The runtime capability contract is an image-level test. For an existing image,
overlay the current firewall script in a small fixture image and verify that
all four capabilities—and no subset—satisfy bootstrap:

```bash
docker build \
  --build-arg BASE_IMAGE=ghcr.io/libops/cli-sandbox:codex \
  -f tests/Dockerfile.runtime-capabilities \
  -t cli-sandbox:runtime-capabilities-test .
bash tests/runtime-capabilities_test.sh cli-sandbox:runtime-capabilities-test
```
