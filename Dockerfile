# renovate: datasource=golang-version depName=go versioning=semver
ARG GO_VERSION=1.27.1
ARG GO_AMD64=linux-amd64.tar.gz
ARG GO_AMD64_SHA256="63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445"
ARG GO_ARM64=linux-arm64.tar.gz
ARG GO_ARM64_SHA256="3450b45a3f9ee8568792736a5c5e70a1f2e9b36c35a8f74958c03e51d7d92bec"

ARG \
  # renovate: datasource=go depName=github.com/docker/buildx
  DOCKER_BUILDX_VERSION=v0.37.0 \
  # renovate: datasource=go depName=github.com/docker/compose/v5
  DOCKER_COMPOSE_VERSION=v5.5.0 \
  # renovate: datasource=go depName=github.com/hashicorp/terraform
  TERRAFORM_VERSION=v1.16.1 \
  TERRAFORM_SOURCE_SHA256=d425d2d781763bf810d6c547a47822d4d0d934ff5311e9e26dc45f4f30c241bd

ARG \
  # renovate: datasource=go depName=github.com/moby/go-archive
  GO_ARCHIVE_VERSION=v0.3.3 \
  # renovate: datasource=go depName=golang.org/x/mod
  GO_MOD_VERSION=v0.40.0 \
  # renovate: datasource=go depName=golang.org/x/net
  GO_NET_VERSION=v0.58.0 \
  # renovate: datasource=go depName=golang.org/x/text
  GO_TEXT_VERSION=v0.41.0 \
  # renovate: datasource=go depName=google.golang.org/grpc
  GRPC_VERSION=v1.83.2

ARG \
  # renovate: datasource=go depName=golang.org/x/tools/gopls
  GOPLS_VERSION=v0.23.0 \
  # renovate: datasource=go depName=golang.org/x/vuln
  GOVULNCHECK_VERSION=v1.7.0 \
  # renovate: datasource=go depName=github.com/securego/gosec/v2
  GOSEC_VERSION=v2.29.0 \
  # renovate: datasource=go depName=github.com/rhysd/actionlint
  ACTIONLINT_VERSION=v1.7.12 \
  # renovate: datasource=go depName=github.com/bufbuild/buf
  BUF_VERSION=v1.72.0 \
  # renovate: datasource=go depName=github.com/sqlc-dev/sqlc
  SQLC_VERSION=v1.31.1

FROM node:24-trixie@sha256:f7d34e58713740f9eef9092c0bd6ff10369d132f7238399a4b270f16d47fa608 AS go-tools-builder

ARG \
  TARGETARCH \
  GO_VERSION \
  GO_AMD64 \
  GO_AMD64_SHA256 \
  GO_ARM64 \
  GO_ARM64_SHA256 \
  DOCKER_BUILDX_VERSION \
  DOCKER_COMPOSE_VERSION \
  TERRAFORM_VERSION \
  TERRAFORM_SOURCE_SHA256 \
  GO_ARCHIVE_VERSION \
  GO_MOD_VERSION \
  GO_NET_VERSION \
  GO_TEXT_VERSION \
  GRPC_VERSION \
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
  go install github.com/securego/gosec/v2/cmd/gosec@"${GOSEC_VERSION}" && \
  go install github.com/rhysd/actionlint/cmd/actionlint@"${ACTIONLINT_VERSION}"

# Each command builds from an isolated module whose dependency versions are
# pinned by the preceding go get calls; hadolint cannot follow go's -C flag.
# hadolint ignore=DL3062
RUN --mount=type=cache,id=go-tools-mod-${TARGETARCH},sharing=locked,target=/root/go/pkg/mod \
  --mount=type=cache,id=go-tools-build-${TARGETARCH},sharing=locked,target=/root/.cache/go-build \
  mkdir -p /tmp/govulncheck /tmp/buf /tmp/sqlc /tmp/buildx /tmp/compose && \
  go -C /tmp/govulncheck mod init cli-sandbox.local/govulncheck && \
  go -C /tmp/govulncheck get golang.org/x/vuln/cmd/govulncheck@"${GOVULNCHECK_VERSION}" && \
  go -C /tmp/govulncheck get golang.org/x/mod@"${GO_MOD_VERSION}" && \
  go -C /tmp/govulncheck build -o /root/go/bin/govulncheck golang.org/x/vuln/cmd/govulncheck && \
  go -C /tmp/buf mod init cli-sandbox.local/buf && \
  go -C /tmp/buf get github.com/bufbuild/buf/cmd/buf@"${BUF_VERSION}" && \
  go -C /tmp/buf get golang.org/x/mod@"${GO_MOD_VERSION}" && \
  go -C /tmp/buf build -o /root/go/bin/buf github.com/bufbuild/buf/cmd/buf && \
  go -C /tmp/sqlc mod init cli-sandbox.local/sqlc && \
  go -C /tmp/sqlc get github.com/sqlc-dev/sqlc/cmd/sqlc@"${SQLC_VERSION}" && \
  go -C /tmp/sqlc get golang.org/x/net@"${GO_NET_VERSION}" golang.org/x/text@"${GO_TEXT_VERSION}" google.golang.org/grpc@"${GRPC_VERSION}" && \
  go -C /tmp/sqlc build -o /root/go/bin/sqlc github.com/sqlc-dev/sqlc/cmd/sqlc && \
  go -C /tmp/buildx mod init cli-sandbox.local/buildx && \
  go -C /tmp/buildx get github.com/docker/buildx/cmd/buildx@"${DOCKER_BUILDX_VERSION}" && \
  go -C /tmp/buildx get github.com/moby/go-archive@"${GO_ARCHIVE_VERSION}" golang.org/x/mod@"${GO_MOD_VERSION}" && \
  go -C /tmp/buildx build -trimpath \
    -ldflags "-s -w -X github.com/docker/buildx/version.Version=${DOCKER_BUILDX_VERSION} -X github.com/docker/buildx/version.Package=github.com/docker/buildx" \
    -o /root/go/bin/docker-buildx github.com/docker/buildx/cmd/buildx && \
  go -C /tmp/compose mod init cli-sandbox.local/compose && \
  go -C /tmp/compose get github.com/docker/compose/v5/cmd@"${DOCKER_COMPOSE_VERSION}" && \
  go -C /tmp/compose get golang.org/x/mod@"${GO_MOD_VERSION}" && \
  go -C /tmp/compose build -trimpath \
    -ldflags "-s -w -X github.com/docker/compose/v5/internal.Version=${DOCKER_COMPOSE_VERSION}" \
    -o /root/go/bin/docker-compose github.com/docker/compose/v5/cmd

RUN --mount=type=cache,id=go-tools-mod-${TARGETARCH},sharing=locked,target=/root/go/pkg/mod \
  --mount=type=cache,id=go-tools-build-${TARGETARCH},sharing=locked,target=/root/.cache/go-build \
  --mount=type=cache,id=go-tools-downloads-${TARGETARCH},sharing=locked,target=/opt/downloads \
  download.sh \
    --url "https://github.com/hashicorp/terraform/archive/refs/tags/${TERRAFORM_VERSION}.tar.gz" \
    --sha256 "${TERRAFORM_SOURCE_SHA256}" \
    --dest /tmp/terraform \
    --strip && \
  go -C /tmp/terraform build -trimpath \
    -ldflags "-s -w -X github.com/hashicorp/terraform/version.dev=no" \
    -o /root/go/bin/terraform .

FROM node:24-trixie@sha256:f7d34e58713740f9eef9092c0bd6ff10369d132f7238399a4b270f16d47fa608

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
  BW_VERSION=0.12.0-1~deb13u1 \
  # Pinned from Docker's test channel until the next stable release includes
  # the Go 1.26.6 security fixes verified by the image vulnerability scan.
  # renovate: datasource=deb depName=docker-ce
  DOCKER_CE_VERSION=5:29.8.0~rc.1-1~debian.13~trixie \
  # renovate: datasource=deb depName=containerd.io
  CONTAINERD_IO_VERSION=2.3.4-1~debian.13~trixie \
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
  # renovate: datasource=repology depName=debian_13/openssl
  LIBSSL_VERSION=3.5.7-1~deb13u2 \
  # renovate: datasource=repology depName=debian_13/linux
  LINUX_LIBC_DEV_VERSION=6.12.107-1 \
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
    'Components: stable test' \
    "Architectures: $(dpkg --print-architecture)" \
    'Signed-By: /etc/apt/keyrings/docker.asc' \
    > /etc/apt/sources.list.d/docker.sources && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    aggregate="${AGGREGATE_VERSION}" \
    bc="${BC_VERSION_HACK}" \
    bind9-dnsutils="${BIND9_VERSION}" \
    bubblewrap="${BW_VERSION}" \
    containerd.io="${CONTAINERD_IO_VERSION}" \
    docker-ce="${DOCKER_CE_VERSION}" \
    docker-ce-cli="${DOCKER_CE_VERSION}" \
    fzf="${FZF_VERSION}" \
    gh="${GH_VERSION}" \
    git="${GIT_VERSION}" \
    gnupg2="${GNUPG2_VERSION}" \
    iproute2="${IPROUTE2_VERSION}" \
    ipset="${IPSET_VERSION}" \
    iptables="${IPTABLES_VERSION}" \
    jq="${JQ_VERSION}" \
    less="${LESS_VERSION}" \
    libssl-dev="${LIBSSL_VERSION}" \
    libssl3t64="${LIBSSL_VERSION}" \
    linux-libc-dev="${LINUX_LIBC_DEV_VERSION}" \
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
    openssl="${LIBSSL_VERSION}" \
    openssl-provider-legacy="${LIBSSL_VERSION}" \
    psmisc="${PSMISC_VERSION}" \
    procps="${PROCPS_VERSION}" \
    ripgrep="${RIPGREP_VERSION}" \
    sudo="${SUDO_VERSION}" \
    tree="${TREE_VERSION}" \
    unzip="${UNZIP_VERSION}" \
    vim="${VIM_VERSION}" && \
  apt-mark hold \
    containerd.io \
    docker-ce \
    docker-ce-cli && \
  sed -i 's/Components: stable test/Components: stable/' /etc/apt/sources.list.d/docker.sources && \
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
COPY --from=go-tools-builder /root/go/bin/terraform /usr/local/bin/
COPY --from=go-tools-builder /root/go/bin/docker-buildx /usr/libexec/docker/cli-plugins/docker-buildx
COPY --from=go-tools-builder /root/go/bin/docker-compose /usr/libexec/docker/cli-plugins/docker-compose

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --chown=root:root --chmod=0555 init-firewall.sh /usr/local/bin/init-firewall.sh
COPY --chown=root:root --chmod=0444 default-route-gateway.awk dns-a-records.awk /usr/local/bin/
COPY --chown=root:root --chmod=0440 node-firewall.sudoers /etc/sudoers.d/node-firewall

# hadolint ignore=DL3066
USER node

ENV \
  NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
  PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/go/bin:/home/node/go/bin:/usr/local/share/npm-global/bin:/home/node/.composer/vendor/bin \
  SHELL=/bin/bash \
  EDITOR=vim \
  COMPOSER_HOME=/home/node/.composer

ARG \
  # renovate: datasource=npm depName=npm
  NPM_VERSION=12.0.2 \
  # renovate: datasource=npm depName=brace-expansion
  NPM_BRACE_EXPANSION_VERSION=5.0.9 \
  # renovate: datasource=npm depName=ip-address
  NPM_IP_ADDRESS_VERSION=10.7.0 \
  # renovate: datasource=npm depName=tar
  NPM_TAR_VERSION=7.5.22 \
  # renovate: datasource=npm depName=@anthropic-ai/claude-code
  CLAUDE_CLI_VERSION=2.1.259 \
  # renovate: datasource=npm depName=@openai/codex
  CODEX_CLI_VERSION=0.153.0 \
  # renovate: datasource=npm depName=@earendil-works/pi-coding-agent
  PI_CLI_VERSION=0.84.4 \
  CLI=""

# hadolint ignore=DL3066
USER root

RUN npm install --global --prefix /usr/local "npm@$NPM_VERSION" && \
  npm install --prefix /tmp/npm-security-patches --no-save --ignore-scripts --no-audit --no-fund \
    "brace-expansion@$NPM_BRACE_EXPANSION_VERSION" \
    "ip-address@$NPM_IP_ADDRESS_VERSION" \
    "tar@$NPM_TAR_VERSION" && \
  rm -rf \
    /usr/local/lib/node_modules/npm/node_modules/brace-expansion \
    /usr/local/lib/node_modules/npm/node_modules/ip-address \
    /usr/local/lib/node_modules/npm/node_modules/tar && \
  cp -a /tmp/npm-security-patches/node_modules/brace-expansion /usr/local/lib/node_modules/npm/node_modules/ && \
  cp -a /tmp/npm-security-patches/node_modules/ip-address /usr/local/lib/node_modules/npm/node_modules/ && \
  cp -a /tmp/npm-security-patches/node_modules/tar /usr/local/lib/node_modules/npm/node_modules/ && \
  rm -rf /tmp/npm-security-patches && \
  chown -R node:node /usr/local/share/npm-global

# hadolint ignore=DL3066
USER node

RUN if [ -n "$CLI" ]; then \
    case "$CLI" in \
      claude) npm install -g --allow-scripts=@anthropic-ai/claude-code,@google/genai,protobufjs "@anthropic-ai/claude-code@$CLAUDE_CLI_VERSION" ;; \
      codex) npm install -g --allow-scripts=@anthropic-ai/claude-code,@google/genai,protobufjs "@openai/codex@$CODEX_CLI_VERSION" ;; \
      pi) npm install -g --allow-scripts=@anthropic-ai/claude-code,@google/genai,protobufjs "@earendil-works/pi-coding-agent@$PI_CLI_VERSION" ;; \
    esac; \
  else \
    npm install -g --allow-scripts=@anthropic-ai/claude-code,@google/genai,protobufjs \
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

RUN if [ -z "$CLI" ] || [ "$CLI" = "claude" ]; then claude install; fi && \
    if [ "$CLI" = "codex" ]; then wget -q -O - https://chatgpt.com/codex/install.sh | sh; fi

ENTRYPOINT [ "/docker-entrypoint.sh" ]
