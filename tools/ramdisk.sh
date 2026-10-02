#!/bin/zsh
# Mount a 64 MB RAM disk at /Volumes/sam2ram for the Lua <-> bridge exchange
# files (bead sam-yku.11). Optional: everything falls back to /tmp/sam2.
# It does not survive a reboot; rerun it then.
set -e
if [ -d /Volumes/sam2ram ]; then echo "already mounted:"; df -h /Volumes/sam2ram | tail -1; exit 0; fi
DEV=$(hdiutil attach -nomount ram://131072 | awk '{print $1}')
diskutil eraseVolume HFS+ sam2ram "$DEV" | tail -1
df -h /Volumes/sam2ram | tail -1
