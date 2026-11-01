#!/usr/bin/env bash
# Nel container: init e sync di LineageOS 18.1 con il manifest locale del 1520.
set -euo pipefail
cd /src
if [ ! -d .repo ]; then
	repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --git-lfs --depth=1
fi
mkdir -p .repo/local_manifests
curl -fsSL -H "Accept: application/vnd.github.raw" \
	"https://api.github.com/repos/giannoccarol/bandit-manifests/contents/lineageos-18.1/bandit_manifest.xml?ref=lineage-18.1" \
	-o .repo/local_manifests/bandit.xml
grep -q "android_device_nokia_bandit" .repo/local_manifests/bandit.xml
repo sync -c -j8 --no-tags --no-clone-bundle --optimized-fetch --prune --fail-fast
echo SYNC-OK
