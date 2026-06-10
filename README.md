# cli-sandbox

Run `claude`, `codex`, `gemini` or `opencode` in a docker container.

`iptables` is used inside the container to block all outbound traffic except GitHub, Anthropic, and Google Cloud internal IPs.

## Requirements

- docker
  - Need to pass `--cap-add=NET_ADMIN --cap-add=NET_RAW` to the `docker run` command for this image to configure the firewall
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

### Using Docker inside the sandbox

The image ships the Docker CLI, so you can drive the host's Docker daemon from
inside the sandbox by bind-mounting the daemon socket.

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
