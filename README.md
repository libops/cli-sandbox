# cli-sandbox

Run `gemini` and `claude` in a docker container.

`iptables` is used inside the container to block all outbound traffic except GitHub, Anthropic, and Google Cloud internal IPs.

## Requirements

- docker
  - Need to pass `--cap-add=NET_ADMIN --cap-add=NET_RAW` to the `docker run` command for this image to configure the firewall
- You will need to mount the codebase you want to work on inside the container
- To persist your auth and settings for gemini and claude, you'll want to mount those directories into `/home/node` (see usage below)

## Usage

```
cd /path/to/codebase
CODE_CLI=claude # or gemini
docker run \
  -v $HOME/.gemini:/home/node/.gemini \
  -v $HOME/.claude:/home/node/.claude \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -v ./:/workspace \
  -w /workspace \
  --rm -it \
  ghcr.io/libops/cli-sandbox:main \
  "$CODE_CLI"
# chit chat
```

If you pass `gemini` or `claude` as the last argument to the `docker run` command you'll get dropped into the respective CLI. If you don't pass anything, you'll be in a bash shell and can run `claude` or `gemini` and switch between the two.

## Attribution

- `Dockerfile` and `init-firewall.sh` forked from [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/.devcontainer). Added gemini support and installed `go`
- `download.sh` copied from [islandora-devops/isle-buildkit](https://github.com/Islandora-Devops/isle-buildkit/tree/main/base/rootfs/usr/local/bin)
