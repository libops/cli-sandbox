# renovate: datasource=golang-version depName=go versioning=semver
ARG GO_VERSION=1.27.0
ARG GO_AMD64=linux-amd64.tar.gz
ARG GO_AMD64_SHA256="675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685"
ARG GO_ARM64=linux-arm64.tar.gz
ARG GO_ARM64_SHA256="51798d2c42d0e1c6ed7fd9f48728b4193abac9e8aad6dbac2fe96a81f5909bda"

ARG \
  # renovate: datasource=go depName=golang.org/x/tools/gopls
  GOPLS_VERSION=v0.23.0 \
  # renovate: datasource=go depName=golang.org/x/vuln
  GOVULNCHECK_VERSION=v1.7.0 \
  # renovate: datasource=go depName=github.com/securego/gosec/v2
  GOSEC_VERSION=v2.28.0 \
  # renovate: datasource=go depName=github.com/rhysd/actionlint
  ACTIONLINT_VERSION=v1.7.12 \
  # renovate: datasource=go depName=github.com/bufbuild/buf
  BUF_VERSION=v1.72.0 \
  # renovate: datasource=go depName=github.com/sqlc-dev/sqlc
  SQLC_VERSION=v1.31.1

FROM node:24-trixie@sha256:66bb8d36ae1ddd72199ed235a089904874ca4079ee517936ca3adb80506a75c1 AS go-tools-builder

ARG \
  TARGETARCH \
  GO_VERSION \
  GO_AMD64 \
  GO_AMD64_SHA256 \
  GO_ARM64 \
  GO_ARM64_SHA256 \
  GOPLS_VERSION \
  GOVULNCHECK_VERSION \
  GOSEC_VERSION \
  ACTIONLINT_VERSION \
  BUF_VERSION \
  SQLC_VERSION

COPY download.sh /usr/local/bin
RUN --mount=type=cache,id=go-tools-downloads-${TARGETARCH},sharing=locked,target=/opt/downloads \
  if [ "${TARGETARCH}" = "amd64" ]; \
  then \
  download.sh \
  --url "https://go.dev/dl/go${GO_VERSION}.${GO_AMD64}" \
  --sha256 "${GO_AMD64_SHA256}" \
  --dest /usr/local ; \
  else \
  download.sh \
  --url "https://go.dev/dl/go${GO_VERSION}.${GO_ARM64}" \
  --sha256 "${GO_ARM64_SHA256}" \
  --dest /usr/local ; \
  fi

ENV PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin

RUN --mount=type=cache,id=go-tools-mod-${TARGETARCH},sharing=locked,target=/root/go/pkg/mod \
  --mount=type=cache,id=go-tools-build-${TARGETARCH},sharing=locked,target=/root/.cache/go-build \
  go install golang.org/x/tools/gopls@"${GOPLS_VERSION}" && \
  go install golang.org/x/vuln/cmd/govulncheck@"${GOVULNCHECK_VERSION}" && \
  go install github.com/securego/gosec/v2/cmd/gosec@"${GOSEC_VERSION}" && \
  go install github.com/rhysd/actionlint/cmd/actionlint@"${ACTIONLINT_VERSION}" && \
  go install github.com/bufbuild/buf/cmd/buf@"${BUF_VERSION}" && \
  go install github.com/sqlc-dev/sqlc/cmd/sqlc@"${SQLC_VERSION}"

FROM node:24-trixie@sha256:66bb8d36ae1ddd72199ed235a089904874ca4079ee517936ca3adb80506a75c1

ARG TZ
ENV TZ="$TZ"

RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share && \
  mkdir -p /workspace /home/node/.claude /home/node/.codex && \
  chown -R node:node /workspace /home/node/.claude /home/node/.codex

WORKDIR /workspace

ARG \
  TARGETARCH \
  # renovate: datasource=repology depName=debian_13/aggregate
  AGGREGATE_VERSION=1.6-8 \
  # renovate: datasource=repology depName=debian_13/bc
  BC_VERSION=1.07.1-4 \
  # renovate: datasource=repology depName=debian_13/bind9
  BIND9_VERSION=1:9.20.26-1~deb13u1 \
  # renovate: datasource=repology depName=debian_13/bubblewrap
  BW_VERSION=0.11.0-2+deb13u1 \
  # renovate: datasource=deb depName=docker-ce
  DOCKER_CE_VERSION=5:29.7.2-1~debian.13~trixie \
  # renovate: datasource=deb depName=containerd.io
  CONTAINERD_IO_VERSION=2.3.3-1~debian.13~trixie \
  # renovate: datasource=deb depName=docker-buildx-plugin
  DOCKER_BUILDX_PLUGIN_VERSION=0.36.1-1~debian.13~trixie \
  # renovate: datasource=deb depName=docker-compose-plugin
  DOCKER_COMPOSE_PLUGIN_VERSION=5.5.0-1~debian.13~trixie \
  # renovate: datasource=repology depName=debian_13/fzf
  FZF_VERSION=0.60.3-1+b2 \
  # renovate: datasource=repology depName=debian_13/gh
  GH_VERSION=2.46.0-3 \
  # renovate: datasource=repology depName=debian_13/git
  GIT_VERSION=1:2.47.3-0+deb13u1 \
  # renovate: datasource=repology depName=debian_13/gnupg2
  GNUPG2_VERSION=2.4.7-21+deb13u1 \
  # renovate: datasource=repology depName=debian_13/iproute2
  IPROUTE2_VERSION=6.15.0-1 \
  # renovate: datasource=repology depName=debian_13/ipset
  IPSET_VERSION=7.22-1+b1 \
  # renovate: datasource=repology depName=debian_13/iptables
  IPTABLES_VERSION=1.8.11-2 \
  # renovate: datasource=repology depName=debian_13/jq
  JQ_VERSION=1.7.1-6+deb13u3 \
  # renovate: datasource=repology depName=debian_13/less
  LESS_VERSION=668-1 \
  # renovate: datasource=repology depName=debian_13/make-dfsg
  MAKE_VERSION=4.4.1-2 \
  # renovate: datasource=repology depName=debian_13/man-db
  MAN_DB_VERSION=2.13.1-1 \
  # renovate: datasource=repology depName=debian_13/man-db
  MARIADB_VERSION=1:11.8.6-0+deb13u1 \
  # renovate: datasource=repology depName=debian_13/patch
  PATCH_VERSION=2.8-2 \
  # renovate: datasource=repology depName=debian_13/php
  PHP_VERSION=2:8.4+96 \
  # renovate: datasource=repology depName=debian_13/composer
  COMPOSER_VERSION=2.8.8-1+deb13u3 \
  # renovate: datasource=repology depName=debian_13/psmisc
  PSMISC_VERSION=23.7-2 \
  # renovate: datasource=repology depName=debian_13/procps
  PROCPS_VERSION=2:4.0.4-9 \
  # renovate: datasource=repology depName=debian_13/ripgrep
  RIPGREP_VERSION=14.1.1-1+b4 \
  # renovate: datasource=repology depName=debian_13/sudo
  SUDO_VERSION=1.9.16p2-3+deb13u2 \
  # renovate: datasource=repology depName=debian_13/terraform
  TERRAFORM_VERSION=1.15.2-1 \
  # renovate: datasource=repology depName=debian_13/tree
  TREE_VERSION=2.2.1-1 \
  # renovate: datasource=repology depName=debian_13/unzip
  UNZIP_VERSION=6.0-29+deb13u1 \
  # renovate: datasource=repology depName=debian_13/vim
  VIM_VERSION=2:9.1.1230-2 \
  GO_VERSION \
  GO_AMD64 \
  GO_AMD64_SHA256 \
  GO_ARM64 \
  GO_ARM64_SHA256

SHELL ["/bin/bash", "-o", "pipefail", "-ex", "-c"]

RUN --mount=type=cache,id=apt-cache-${TARGETARCH},sharing=locked,target=/var/cache/apt \
  BC_VERSION_HACK="${BC_VERSION}$([ "${TARGETARCH}" = "arm64" ] && echo "+b1" || echo "")" && \
  rm -f /etc/apt/apt.conf.d/docker-clean && \
  install -m 0755 -d /etc/apt/keyrings && \
  wget -q -O /etc/apt/keyrings/docker.asc https://download.docker.com/linux/debian/gpg && \
  chmod a+r /etc/apt/keyrings/docker.asc && \
  printf '%s\n' \
    'Types: deb' \
    'URIs: https://download.docker.com/linux/debian' \
    'Suites: trixie' \
    'Components: stable' \
    "Architectures: $(dpkg --print-architecture)" \
    'Signed-By: /etc/apt/keyrings/docker.asc' \
    > /etc/apt/sources.list.d/docker.sources && \
  wget -q -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com trixie main" | tee /etc/apt/sources.list.d/hashicorp.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    aggregate="${AGGREGATE_VERSION}" \
    bc="${BC_VERSION_HACK}" \
    bind9-dnsutils="${BIND9_VERSION}" \
    bubblewrap="${BW_VERSION}" \
    containerd.io="${CONTAINERD_IO_VERSION}" \
    docker-buildx-plugin="${DOCKER_BUILDX_PLUGIN_VERSION}" \
    docker-ce="${DOCKER_CE_VERSION}" \
    docker-ce-cli="${DOCKER_CE_VERSION}" \
    docker-compose-plugin="${DOCKER_COMPOSE_PLUGIN_VERSION}" \
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
    mariadb-client="${MARIADB_VERSION}" \
    patch="${PATCH_VERSION}" \
    php="${PHP_VERSION}" \
    composer="${COMPOSER_VERSION}" \
    php-cli="${PHP_VERSION}" \
    php-curl="${PHP_VERSION}" \
    php-gd="${PHP_VERSION}" \
    php-intl="${PHP_VERSION}" \
    php-mbstring="${PHP_VERSION}" \
    php-mysql="${PHP_VERSION}" \
    php-sqlite3="${PHP_VERSION}" \
    php-xml="${PHP_VERSION}" \
    php-zip="${PHP_VERSION}" \
    psmisc="${PSMISC_VERSION}" \
    procps="${PROCPS_VERSION}" \
    ripgrep="${RIPGREP_VERSION}" \
    sudo="${SUDO_VERSION}" \
    tree="${TREE_VERSION}" \
    unzip="${UNZIP_VERSION}" \
    vim="${VIM_VERSION}" \
    terraform="${TERRAFORM_VERSION}" && \
  apt-mark hold \
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin && \
  rm -rf /var/lib/apt/lists/*

COPY download.sh /usr/local/bin
RUN --mount=type=cache,id=base-downloads-${TARGETARCH},sharing=locked,target=/opt/downloads \
  if [ "${TARGETARCH}" = "amd64" ]; \
  then \
  download.sh \
  --url "https://go.dev/dl/go${GO_VERSION}.${GO_AMD64}" \
  --sha256 "${GO_AMD64_SHA256}" \
  --dest /usr/local ; \
  else \
  download.sh \
  --url "https://go.dev/dl/go${GO_VERSION}.${GO_ARM64}" \
  --sha256 "${GO_ARM64_SHA256}" \
  --dest /usr/local ; \
  fi

ENV PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/go/bin:/usr/local/share/npm-global/bin:/home/node/.composer/vendor/bin

RUN printf '%s\n' \
  "export PATH=\"/usr/local/go/bin:/home/node/go/bin:/usr/local/share/npm-global/bin:/home/node/.composer/vendor/bin:\$PATH\"" \
  > /etc/profile.d/cli-sandbox-path.sh && \
  chmod 0644 /etc/profile.d/cli-sandbox-path.sh

COPY --from=go-tools-builder /root/go/bin/gopls /usr/local/bin/
COPY --from=go-tools-builder /root/go/bin/govulncheck /usr/local/bin/
COPY --from=go-tools-builder /root/go/bin/gosec /usr/local/bin/
COPY --from=go-tools-builder /root/go/bin/actionlint /usr/local/bin/
COPY --from=go-tools-builder /root/go/bin/sqlc /usr/local/bin/
COPY --from=go-tools-builder /root/go/bin/buf /usr/local/bin/

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --chown=root:root --chmod=0555 init-firewall.sh /usr/local/bin/init-firewall.sh
COPY --chown=root:root --chmod=0444 default-route-gateway.awk dns-a-records.awk /usr/local/bin/
COPY --chown=root:root --chmod=0440 node-firewall.sudoers /etc/sudoers.d/node-firewall

USER node

ENV \
  NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
  PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/go/bin:/home/node/go/bin:/usr/local/share/npm-global/bin:/home/node/.composer/vendor/bin \
  SHELL=/bin/bash \
  EDITOR=vim \
  COMPOSER_HOME=/home/node/.composer

ARG \
  # renovate: datasource=npm depName=@anthropic-ai/claude-code
  CLAUDE_CLI_VERSION=2.1.239 \
  # renovate: datasource=npm depName=@openai/codex
  CODEX_CLI_VERSION=0.149.1 \
  # renovate: datasource=npm depName=@earendil-works/pi-coding-agent
  PI_CLI_VERSION=0.84.2 \
  CLI=""

RUN if [ -n "$CLI" ]; then \
    case "$CLI" in \
      claude) npm install -g "@anthropic-ai/claude-code@$CLAUDE_CLI_VERSION" ;; \
      codex) npm install -g "@openai/codex@$CODEX_CLI_VERSION" ;; \
      pi) npm install -g "@earendil-works/pi-coding-agent@$PI_CLI_VERSION" ;; \
    esac; \
  else \
    npm install -g \
      "@anthropic-ai/claude-code@$CLAUDE_CLI_VERSION" \
      "@openai/codex@$CODEX_CLI_VERSION" \
      "@earendil-works/pi-coding-agent@$PI_CLI_VERSION"; \
  fi

COPY force-tty.js /home/node/.force-tty.js

ENV \
  NODE_OPTIONS="--max-old-space-size=4096 --require /home/node/.force-tty.js" \
  CLAUDE_CONFIG_DIR="/home/node/.claude" \
  CODEX_HOME="/home/node/.codex" \
  COMPOSER_HOME="/home/node/.composer" \
  COMPOSER_MEMORY_LIMIT=-1 \
  PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/go/bin:/home/node/go/bin:/usr/local/share/npm-global/bin:/home/node/.composer/vendor/bin \
  CLI_SANDBOX_EGRESS_PROFILE="managed" \
  SKIP_EGRESS_FIREWALL="false"

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY .bash_aliases /home/node/

RUN if [ -z "$CLI" ] || [ "$CLI" = "claude" ]; then claude install; fi

ENTRYPOINT [ "/docker-entrypoint.sh" ]
