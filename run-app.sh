#!/bin/bash
set -e

echo "[RsyncGUI] Building app bundle..."
./scripts/build_app.sh

echo "[RsyncGUI] Launching..."
open RsyncGUI.app
