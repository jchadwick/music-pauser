#!/usr/bin/env bash
set -euo pipefail

REPO="jchadwick/music-pauser"
APP_NAME="MusicPauser.app"
INSTALL_DIR="/Applications"
ASSET_NAME="MusicPauser.zip"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "==> Fetching latest release URL..."
DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep "browser_download_url" \
  | grep "${ASSET_NAME}" \
  | sed 's/.*"browser_download_url": "\(.*\)"/\1/')

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Error: could not find a release asset named ${ASSET_NAME}." >&2
  echo "Make sure a release has been published at https://github.com/${REPO}/releases" >&2
  exit 1
fi

echo "==> Downloading ${DOWNLOAD_URL}..."
curl -fsSL "$DOWNLOAD_URL" -o "${TMP_DIR}/${ASSET_NAME}"

echo "==> Stopping MusicPauser if running..."
pkill -f "${APP_NAME}" 2>/dev/null || true
sleep 1

echo "==> Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_NAME}"
unzip -q "${TMP_DIR}/${ASSET_NAME}" -d "$TMP_DIR"
cp -R "${TMP_DIR}/${APP_NAME}" "${INSTALL_DIR}/${APP_NAME}"

echo "==> Clearing quarantine flag..."
xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}" 2>/dev/null || true

echo "==> Launching MusicPauser..."
open "${INSTALL_DIR}/${APP_NAME}"

echo "Done. MusicPauser is running."
