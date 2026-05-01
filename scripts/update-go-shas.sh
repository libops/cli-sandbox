#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${ROOT_DIR}/Dockerfile"
METADATA_URL="https://go.dev/dl/?mode=json&include=all"

GO_VERSION="$(sed -n 's/^ARG GO_VERSION=\(.*\)$/\1/p' "${DOCKERFILE}" | head -n1)"

if [ -z "${GO_VERSION}" ]; then
  echo "Unable to find ARG GO_VERSION in ${DOCKERFILE}" >&2
  exit 1
fi

metadata="$(curl -fsSL "${METADATA_URL}")"

function sha256_for_arch {
  local arch="${1}"
  local filename="go${GO_VERSION}.linux-${arch}.tar.gz"
  local sha256

  sha256="$(jq -r \
    --arg release "go${GO_VERSION}" \
    --arg filename "${filename}" \
    '.[] | select(.version == $release) | .files[] | select(.filename == $filename) | .sha256' \
    <<<"${metadata}")"

  if [ -z "${sha256}" ] || [ "${sha256}" = "null" ]; then
    echo "Unable to find sha256 for ${filename} in ${METADATA_URL}" >&2
    exit 1
  fi

  printf '%s\n' "${sha256}"
}

function replace_sha_arg {
  local name="${1}"
  local sha256="${2}"

  if ! grep -Eq "^ARG ${name}=\"[0-9a-f]{64}\"" "${DOCKERFILE}"; then
    echo "Unable to find ARG ${name} in ${DOCKERFILE}" >&2
    exit 1
  fi

  sed -i -E "s/^(ARG ${name}=)\"[0-9a-f]{64}\"/\\1\"${sha256}\"/" "${DOCKERFILE}"
}

replace_sha_arg GO_AMD64_SHA256 "$(sha256_for_arch amd64)"
replace_sha_arg GO_ARM64_SHA256 "$(sha256_for_arch arm64)"
