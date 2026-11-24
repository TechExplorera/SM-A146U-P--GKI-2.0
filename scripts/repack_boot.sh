#!/usr/bin/env bash
# Inserta un Image nuevo en el boot.img STOCK de tu firmware y genera:
#   boot.img  y  boot.tar (para Odin, slot AP)
#
# Uso: scripts/repack_boot.sh <boot.img | boot.img.lz4> <Image> <carpeta_salida>
# Requiere magiskboot en PATH (el workflow lo extrae del APK de Magisk).
set -euo pipefail

STOCK="$(readlink -f "$1")"; IMAGE="$(readlink -f "$2")"; OUT="$(mkdir -p "$3" && readlink -f "$3")"
command -v magiskboot >/dev/null || { echo "magiskboot no está en PATH" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

case "$STOCK" in
    *.lz4) lz4 -d -f "$STOCK" boot.img >/dev/null ;;
    *)     cp "$STOCK" boot.img ;;
esac

magiskboot unpack -h boot.img
[ -f kernel ] || { echo "El boot.img no contiene kernel (¿es init_boot/vendor_boot?)" >&2; exit 1; }
cp "$IMAGE" kernel
magiskboot repack boot.img new-boot.img

cp new-boot.img "$OUT/boot.img"
( cd "$OUT" && tar -H ustar -cf boot.tar boot.img )
echo "Generado: $OUT/boot.img y $OUT/boot.tar"
