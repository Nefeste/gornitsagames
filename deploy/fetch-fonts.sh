#!/usr/bin/env bash
# Скачивает шрифты сайта (Kurale и Onest, лицензия SIL OFL) в site/assets/fonts,
# если их там ещё нет. Шрифты берутся из npm-пакетов @fontsource через jsDelivr.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT_DIR}/site/assets/fonts"
CDN="https://cdn.jsdelivr.net/npm"
mkdir -p "${DEST}"

get() {
  local url="$1" out="$2"
  if [[ ! -s "${DEST}/${out}" ]]; then
    curl -fsSL --retry 3 -o "${DEST}/${out}.part" "${url}"
    mv "${DEST}/${out}.part" "${DEST}/${out}"
    echo "   скачан ${out}"
  fi
}

for subset in cyrillic latin; do
  get "${CDN}/@fontsource/kurale@5.3.0/files/kurale-${subset}-400-normal.woff2" "kurale-${subset}-400-normal.woff2"
  for weight in 400 500 600; do
    get "${CDN}/@fontsource/onest@5.3.1/files/onest-${subset}-${weight}-normal.woff2" "onest-${subset}-${weight}-normal.woff2"
  done
done
get "${CDN}/@fontsource/kurale@5.3.0/LICENSE" "OFL-Kurale.txt"
get "${CDN}/@fontsource/onest@5.3.1/LICENSE" "OFL-Onest.txt"
