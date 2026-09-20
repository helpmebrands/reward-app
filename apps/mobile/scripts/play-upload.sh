#!/usr/bin/env bash
# Upload an app bundle to the Play internal testing track with the Play
# Developer API, authenticated by a short-lived access token.
#
# fastlane's `supply` and the popular upload actions all want a service
# account JSON key, which this project deliberately does not have: the
# release workflow mints PLAY_ACCESS_TOKEN keylessly as the Play publisher
# identity (workload identity federation) and this script uses it directly.
# Four calls: open an edit, upload the bundle into it, assign the resulting
# version code to the internal track, commit the edit.
#
# Usage: play-upload.sh <package name> <path to .aab>
# Env:   PLAY_ACCESS_TOKEN  bearer token with the androidpublisher scope
set -euo pipefail

package="${1:?package name}"
bundle="${2:?path to .aab}"
: "${PLAY_ACCESS_TOKEN:?PLAY_ACCESS_TOKEN is required}"

api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${package}"
upload="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${package}"
auth=(-H "Authorization: Bearer ${PLAY_ACCESS_TOKEN}")

call() {
  # curl that fails loudly on a non-2xx, printing the body for the log.
  local out
  out="$(curl -sS --fail-with-body "${auth[@]}" "$@")" || { echo "$out" >&2; return 1; }
  echo "$out"
}

edit_id="$(call -X POST "${api}/edits" -H 'Content-Type: application/json' -d '{}' | jq -r .id)"
echo "edit ${edit_id} opened"

version_code="$(call -X POST "${upload}/edits/${edit_id}/bundles?uploadType=media" \
  -H 'Content-Type: application/octet-stream' --data-binary "@${bundle}" | jq -r .versionCode)"
echo "bundle uploaded as version code ${version_code}"

call -X PUT "${api}/edits/${edit_id}/tracks/internal" -H 'Content-Type: application/json' \
  -d "{\"track\":\"internal\",\"releases\":[{\"versionCodes\":[\"${version_code}\"],\"status\":\"completed\"}]}" >/dev/null
echo "assigned to the internal track"

call -X POST "${api}/edits/${edit_id}:commit" >/dev/null
echo "edit ${edit_id} committed: version code ${version_code} is live on the internal track"
