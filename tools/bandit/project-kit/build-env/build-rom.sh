#!/usr/bin/env bash
# Nel container: aggiorna i repository del 1520 e compila LineageOS 18.1
# (lineage_bandit-userdebug). Uscita in /src/out/target/product/bandit/.
# Uso (dall'host): build-env/run.sh bash /env/build-rom.sh [target, default bacon]
set -o pipefail
cd /src
repo sync -c -j4 --no-tags --no-clone-bundle device/nokia/bandit vendor/nokia/bandit kernel/nokia/msm8974 || exit 1
for p in device/nokia/bandit kernel/nokia/msm8974; do echo "$p: $(git -C $p log -1 --format='%h %s')"; done
source build/envsetup.sh >/dev/null
lunch lineage_bandit-userdebug || exit 1
m -k -j16 "${1:-bacon}" 2>&1
rc=${PIPESTATUS[0]}
echo "BUILD-EXIT $rc"
exit $rc
