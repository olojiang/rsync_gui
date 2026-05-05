#!/bin/bash
set -e

echo "[Rsync 纪] Building app bundle..."
./scripts/build_app.sh

echo "[Rsync 纪] Launching..."
open "Rsync 纪.app"
