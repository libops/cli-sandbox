FROM node:24-trixie@sha256:1501d5fd51032aa10701a7dcc9e6c72ab1e611a033ffcf08b6d5882e9165f63e

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
  CLAUDE_CLI_VERSION=v2.0.60 \
  # renovate: datasource=npm depName=@google/gemini-cli
  GEMINI_CLI_VERSION=v0.19.4

RUN npm install -g "@anthropic-ai/claude-code@$CLAUDE_CLI_VERSION" && \
  npm install -g "@google/gemini-cli@$GEMINI_CLI_VERSION"

USER root
ARG \
  TARGETARCH \
  # renovate: datasource=repology depName=debian_13/aggregate
  AGGREGATE_VERSION=1.6-7+b1 \
  # renovate: datasource=repology depName=debian_13/dnsutils
  DNSUTILS_VERSION=1:9.18.41-1~deb12u1 \
  # renovate: datasource=repology depName=debian_13/fzf
  FZF_VERSION=0.38.0-1+b1 \
  # renovate: datasource=repology depName=debian_13/gh
  GH_VERSION=2.23.0+dfsg1-1 \
  # renovate: datasource=repology depName=debian_13/git
  GIT_VERSION=1:2.39.5-0+deb12u2 \
  # renovate: datasource=repology depName=debian_13/gnupg2
  GNUPG2_VERSION=2.2.40-1.1+deb12u1 \
  # renovate: datasource=repology depName=debian_13/iproute2
  IPROUTE2_VERSION=6.1.0-3 \
  # renovate: datasource=repology depName=debian_13/ipset
  IPSET_VERSION=7.17-1 \
  # renovate: datasource=repology depName=debian_13/iptables
  IPTABLES_VERSION=1.8.9-2 \
  # renovate: datasource=repology depName=debian_13/jq
  JQ_VERSION=1.6-2.1+deb12u1 \
  # renovate: datasource=repology depName=debian_13/less
  LESS_VERSION=590-2.1~deb12u2 \
  # renovate: datasource=repology depName=debian_13/make
  MAKE_VERSION=4.3-4.1 \
  # renovate: datasource=repology depName=debian_13/man-db
  MAN_DB_VERSION=2.11.2-2 \
  # renovate: datasource=repology depName=debian_13/procps
  PROCPS_VERSION=2:4.0.2-3 \
  # renovate: datasource=repology depName=debian_13/sudo
  SUDO_VERSION=1.9.13p3-1+deb12u2 \
  # renovate: datasource=repology depName=debian_13/unzip
  UNZIP_VERSION=6.0-28 \
  # renovate: datasource=repology depName=debian_13/vim
  VIM_VERSION=2:9.0.1378-2+deb12u2 \
  # renovate: datasource=github-tags depName=golang packageName=golang/go versioning=go-mod-directive
  GO_VERSION=go1.25.3 \
  GO_BASE_URL="https://go.dev/dl/${GO_VERSION}" \
  GO_AMD64=linux-amd64.tar.gz	\
  GO_AMD64_SHA256="0335f314b6e7bfe08c3d0cfaa7c19db961b7b99fb20be62b0a826c992ad14e0f" \
  GO_ARM64=linux-arm64.tar.gz \
  GO_ARM64_SHA256="1d42ebc84999b5e2069f5e31b67d6fc5d67308adad3e178d5a2ee2c9ff2001f5"

RUN apt-get update && apt-get install -y --no-install-recommends \
  aggregate="${AGGREGATE_VERSION}" \
  dnsutils="${DNSUTILS_VERSION}" \
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
  procps="${PROCPS_VERSION}" \
  sudo="${SUDO_VERSION}" \
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

COPY --chown=node init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

USER node
ENV \
  NODE_OPTIONS="--max-old-space-size=4096" \
  CLAUDE_CONFIG_DIR="/home/node/.claude" \
  POWERLEVEL9K_DISABLE_GITSTATUS="true"

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY .bash_aliases /home/node/

ENTRYPOINT [ "/docker-entrypoint.sh" ]
