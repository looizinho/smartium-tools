#!/usr/bin/env bash
#
# Compila o scheme "App Debug", instala e abre o app num iPhone físico.
#
# Uso: scripts/run_iphone_device.sh <UDID> [--console]
#   <UDID>      identificador do aparelho (veja: xcrun devicectl list devices)
#   --console   mostra os logs do app no terminal; Ctrl+C encerra
#
# O build vai para o DerivedData configurado no Xcode, o mesmo dos builds feitos por ele.

set -euo pipefail

usage() {
  echo "Uso: $0 <UDID> [--console]" >&2
  echo "Aparelhos conectados:" >&2
  xcrun devicectl list devices >&2 || true
  exit 1
}

[[ $# -ge 1 && -n "$1" ]] || usage
device="$1"
console=""
if [[ "${2:-}" == "--console" ]]; then
  console="--console"
elif [[ -n "${2:-}" ]]; then
  usage
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
project="$project_dir/SmartiumTools.xcodeproj"
scheme="App Debug"
bundle_id="dev.smartium.SmartiumTools"

echo "==> Compilando \"$scheme\" para $device"
xcodebuild -project "$project" -scheme "$scheme" \
  -destination "id=$device" -allowProvisioningUpdates build

app="$(xcodebuild -project "$project" -scheme "$scheme" \
  -destination "id=$device" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ TARGET_BUILD_DIR /{dir=$2} / FULL_PRODUCT_NAME /{name=$2} END{print dir "/" name}')"
[[ -d "$app" ]] || { echo "App não encontrado: $app" >&2; exit 1; }

echo "==> Instalando $app"
xcrun devicectl device install app --device "$device" "$app"

echo "==> Abrindo $bundle_id (o iPhone precisa estar desbloqueado)"
xcrun devicectl device process launch $console --device "$device" "$bundle_id"
