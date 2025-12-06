# cli-sandbox

Run `gemini` and `claude` in a docker container

## Usage

```
cd /path/to/codebase
docker run \
  -v $HOME/.gemini:/home/node/.gemini \
  -v $HOME/.claude:/home/node/.claude \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -v ./:/workspace \
  -w /workspace \
  --rm -it ghcr.io/joecorall/cli-sandbox:main
# chit chat
```

## Attribution

`Dockerfile` and `init-firewall.sh` forked from [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/.devcontainer). Added gemini support
