FROM node:24-trixie@sha256:9fabb41bc32c72b02fd332bb6b6a17e01117d7eaa379a497a5adf7e1651baa2b

ARG TZ
ENV TZ="$TZ"

RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share && \
  mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

USER node
ENV \
  NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
  PATH=$PATH:/usr/local/share/npm-global/bin \
  SHELL=/bin/bash \
  EDITOR=vim

ARG \
  # renovate: datasource=npm depName=@anthropic-ai/claude-code
  CLAUDE_CLI_VERSION=2.0.76 \
  # renovate: datasource=npm depName=@google/gemini-cli
  GEMINI_CLI_VERSION=0.22.2 \
  # renovate: datasource=npm depName=opencode-ai
  OPENCODE_AI_VERSION=1.0.193

RUN npm install -g \
  "@anthropic-ai/claude-code@$CLAUDE_CLI_VERSION" \
  "@google/gemini-cli@$GEMINI_CLI_VERSION" \
  "opencode-ai@$OPENCODE_AI_VERSION"

USER root
ARG \
  TARGETARCH \
  # renovate: datasource=repology depName=debian_13/aggregate
  AGGREGATE_VERSION=1.6-8 \
  # renovate: datasource=repology depName=debian_13/bc
  BC_VERSION=1.07.1-4 \
  # renovate: datasource=repology depName=debian_13/bind9
  BIND9_VERSION=1:9.20.15-1~deb13u1 \
  # renovate: datasource=repology depName=debian_13/fzf
  FZF_VERSION=0.60.3-1+b2 \
  # renovate: datasource=repology depName=debian_13/gh
  GH_VERSION=2.46.0-3 \
  # renovate: datasource=repology depName=debian_13/git
  GIT_VERSION=1:2.47.3-0+deb13u1 \
  # renovate: datasource=repology depName=debian_13/gnupg2
  GNUPG2_VERSION=2.4.7-21 \
  # renovate: datasource=repology depName=debian_13/iproute2
  IPROUTE2_VERSION=6.15.0-1 \
  # renovate: datasource=repology depName=debian_13/ipset
  IPSET_VERSION=7.22-1+b1 \
  # renovate: datasource=repology depName=debian_13/iptables
  IPTABLES_VERSION=1.8.11-2 \
  # renovate: datasource=repology depName=debian_13/jq
  JQ_VERSION=1.7.1-6+deb13u1 \
  # renovate: datasource=repology depName=debian_13/less
  LESS_VERSION=668-1 \
  # renovate: datasource=repology depName=debian_13/make-dfsg
  MAKE_VERSION=4.4.1-2 \
  # renovate: datasource=repology depName=debian_13/man-db
  MAN_DB_VERSION=2.13.1-1 \
  # renovate: datasource=repology depName=debian_13/psmisc
  PSMISC_VERSION=23.7-2 \
  # renovate: datasource=repology depName=debian_13/procps
  PROCPS_VERSION=2:4.0.4-9 \
  # renovate: datasource=repology depName=debian_13/ripgrep
  RIPGREP_VERSION=14.1.1-1+b4 \
  # renovate: datasource=repology depName=debian_13/sudo
  SUDO_VERSION=1.9.16p2-3 \
  # renovate: datasource=repology depName=debian_13/tree
  TREE_VERSION=2.2.1-1 \
  # renovate: datasource=repology depName=debian_13/unzip
  UNZIP_VERSION=6.0-29 \
  # renovate: datasource=repology depName=debian_13/vim
  VIM_VERSION=2:9.1.1230-2 \
  # renovate: datasource=github-tags depName=golang packageName=golang/go versioning=go-mod-directive
  GO_VERSION=go1.25.5 \
  GO_BASE_URL="https://go.dev/dl/${GO_VERSION}" \
  GO_AMD64=linux-amd64.tar.gz	\
  GO_AMD64_SHA256="9e9b755d63b36acf30c12a9a3fc379243714c1c6d3dd72861da637f336ebb35b" \
  GO_ARM64=linux-arm64.tar.gz \
  GO_ARM64_SHA256="b00b694903d126c588c378e72d3545549935d3982635ba3f7a964c9fa23fe3b9"

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
  aggregate="${AGGREGATE_VERSION}" \
  bc \
  bind9-dnsutils="${BIND9_VERSION}" \
  fzf="${FZF_VERSION}" \
  gh="${GH_VERSION}" \
  git="${GIT_VERSION}" \
  gnupg2="${GNUPG2_VERSION}" \
  iproute2="${IPROUTE2_VERSION}" \
  ipset="${IPSET_VERSION}" \
  iptables="${IPTABLES_VERSION}" \
  jq="${JQ_VERSION}" \
  less="${LESS_VERSION}" \
  make="${MAKE_VERSION}" \
  man-db="${MAN_DB_VERSION}" \
  psmisc="${PSMISC_VERSION}" \
  procps="${PROCPS_VERSION}" \
  ripgrep \
  sudo="${SUDO_VERSION}" \
  tree="${TREE_VERSION}" \
  unzip="${UNZIP_VERSION}" \
  vim="${VIM_VERSION}" \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY download.sh /usr/local/bin
RUN --mount=type=cache,id=base-downloads-${TARGETARCH},sharing=locked,target=/opt/downloads \
  if [ "${TARGETARCH}" = "amd64" ]; \
  then \
  download.sh \
  --url "${GO_BASE_URL}.${GO_AMD64}" \
  --sha256 "${GO_AMD64_SHA256}" \
  --dest /usr/local ; \
  else \
  download.sh \
  --url "${GO_BASE_URL}.${GO_ARM64}" \
  --sha256 "${GO_ARM64_SHA256}" \
  --dest /usr/local ; \
  fi

ENV PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/go/bin:/usr/local/share/npm-global/bin
COPY --chown=node init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall && \
  go install github.com/sqlc-dev/sqlc/cmd/sqlc@v1.30.0 && \
  go install github.com/bufbuild/buf/cmd/buf@v1.61.0

USER node

COPY force-tty.js /home/node/.force-tty.js

ENV \
  NODE_OPTIONS="--max-old-space-size=4096 --require /home/node/.force-tty.js" \
  CLAUDE_CONFIG_DIR="/home/node/.claude" \
  PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/go/bin:/usr/local/share/npm-global/bin

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY .bash_aliases /home/node/

ENTRYPOINT [ "/docker-entrypoint.sh" ]
