#!/bin/bash
set -e

# Usage: inject_privacy_manifests.sh <frameworks_dir>
# Example: inject_privacy_manifests.sh "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

TARGET_FW_DIR="$1"
if [ -z "$TARGET_FW_DIR" ]; then
  echo "[privacy-manifest] No target dir provided. Exiting."
  exit 1
fi

echo "[privacy-manifest] target frameworks dir: $TARGET_FW_DIR"

# Add any frameworks here that Apple requires a privacy manifest for (common list).
FRAMEWORKS=(
  "flutter_local_notifications.framework"
  "FirebaseMessaging.framework"
  "FirebaseCore.framework"
  "FirebaseInstallations.framework"
  "FirebaseCoreInternal.framework"
  "geolocator_apple.framework"
  "geocoding_ios.framework"
)

for fw in "${FRAMEWORKS[@]}"; do
  if [ -d "$TARGET_FW_DIR/$fw" ]; then
    echo "[privacy-manifest] injecting manifest into $fw"
    cat > "$TARGET_FW_DIR/$fw/PrivacyManifest.json" <<'JSON'
{
  "AppPrivacyConfiguration": {
    "NSPrivacyCollectedDataTypes": []
  }
}
JSON
  else
    echo "[privacy-manifest] framework not present: $fw (skipping)"
  fi
done

echo "[privacy-manifest] done"
