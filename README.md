# cli-sandbox

Run `claude`, `gemini` or `opencode` in a docker container.

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
  if [ "$cli" ] != "opencode" ] && [ "$cli" != "claude" ] && [ "$cli" != "gemini" ]; then
    echo "Need to pass opencode, gemini, or claude"
    return
  fi

  if [ "$(pwd)" = "$HOME" ]; then
    echo "You should cd into your codebase"
    echo "Running this command here would mount your entire home directory into $cli"
    return
  fi

  docker run \
    -v $HOME/.$cli:/home/node/.$cli \
    --cap-add=NET_ADMIN --cap-add=NET_RAW \
    -e COLUMNS=$(tput cols) \
    -e LINES=$(tput lines) \
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

opencode() {
  ccli opencode
}
```

## Attribution

- `Dockerfile` and `init-firewall.sh` forked from [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/.devcontainer). Added gemini support and installed `go`
- `download.sh` copied from [islandora-devops/isle-buildkit](https://github.com/Islandora-Devops/isle-buildkit/tree/main/base/rootfs/usr/local/bin)
