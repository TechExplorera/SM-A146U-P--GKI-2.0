#!/usr/bin/env bash
# Compila el kernel GKI (Image) del Galaxy A14 5G (SM-A146U / a14xm, MT6833)
# a partir del código stock de Samsung, con KernelSU-Next integrado.
#
# Reproduce la config que genera el build oficial (Kleaf/mgk, modo "user"):
#   gki_defconfig + mediatek-bazel_defconfig + mt6833_overlay + S96901AA1 + S96901AA1_debug
# y le aplica scripts/configs/ksu.config (KSU=y, DEFEX off).
#
# Uso:
#   scripts/build_ksu.sh                      # KernelSU-Next (tag por defecto)
#   KSU=none scripts/build_ksu.sh             # kernel stock sin root
#   KSU_REF=v3.4.2 CLANG_DIR=/ruta/clang-r510928 JOBS=8 scripts/build_ksu.sh
#
# Variables:
#   KSU        next | none                (por defecto: next)
#   KSU_REF    tag/commit de KernelSU-Next (por defecto: v3.4.2)
#   CLANG_DIR  raíz de un Clang/LLVM (con bin/clang). Vacío = Clang del sistema.
#   JOBS       hilos de make               (por defecto: nproc)
#   OUT_DIR    carpeta de salida           (por defecto: <repo>/out)
#   LOCALVERSION_SUFFIX  sufijo extra para uname -r (por defecto: vacío)
#   EXTRA_CONFIG  fragmento .config adicional opcional
#   CONFIG_ONLY=1 sólo genera y valida la .config, sin compilar

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$ROOT/kernel-6.6"
DM_DIR="$ROOT/kernel/kernel_device_modules-6.6"

KSU="${KSU:-next}"
KSU_REF="${KSU_REF:-v3.4.2}"
KSU_REPO="${KSU_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
CLANG_DIR="${CLANG_DIR:-}"
JOBS="${JOBS:-$(nproc)}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
LOCALVERSION_SUFFIX="${LOCALVERSION_SUFFIX:-}"
EXTRA_CONFIG="${EXTRA_CONFIG:-}"

BUILD_OBJ="$OUT_DIR/obj"
DIST="$OUT_DIR/dist"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- toolchain
if [ -n "$CLANG_DIR" ]; then
    [ -x "$CLANG_DIR/bin/clang" ] || die "No existe $CLANG_DIR/bin/clang"
    export PATH="$CLANG_DIR/bin:$PATH"
fi
command -v clang >/dev/null || die "clang no encontrado (instala clang/lld/llvm o define CLANG_DIR)"
command -v ld.lld >/dev/null || die "ld.lld no encontrado"
log "Toolchain: $(clang --version | head -1)"

# ------------------------------------------------------------- KernelSU-Next
setup_ksu() {
    local ksu_src="$KERNEL_DIR/KernelSU-Next"
    if [ ! -d "$ksu_src/.git" ]; then
        log "Clonando KernelSU-Next ($KSU_REF)"
        # Historial completo: el Makefile de KSU calcula la versión con rev-list --count.
        git clone --quiet "$KSU_REPO" "$ksu_src"
    fi
    git -C "$ksu_src" fetch --quiet --tags origin
    git -C "$ksu_src" checkout --quiet "$KSU_REF"
    log "KernelSU-Next en $(git -C "$ksu_src" describe --tags --always)"

    ln -sfn ../KernelSU-Next/kernel "$KERNEL_DIR/drivers/kernelsu"
    grep -q 'kernelsu/' "$KERNEL_DIR/drivers/Makefile" || \
        printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_DIR/drivers/Makefile"
    grep -q 'drivers/kernelsu/Kconfig' "$KERNEL_DIR/drivers/Kconfig" || \
        sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig"
}

cleanup_ksu() {
    rm -f "$KERNEL_DIR/drivers/kernelsu"
    sed -i '/obj-\$(CONFIG_KSU) += kernelsu\//d' "$KERNEL_DIR/drivers/Makefile"
    sed -i '/source "drivers\/kernelsu\/Kconfig"/d' "$KERNEL_DIR/drivers/Kconfig"
}

case "$KSU" in
    next) setup_ksu ;;
    none) cleanup_ksu; log "Compilando kernel stock (sin KernelSU)" ;;
    *) die "KSU debe ser 'next' o 'none'" ;;
esac

# ------------------------------------------------------------------ config
MAKE_ARGS=(
    -C "$KERNEL_DIR" O="$BUILD_OBJ"
    ARCH=arm64 LLVM=1 LLVM_IAS=1
    CROSS_COMPILE=aarch64-linux-gnu-
    KCFLAGS="-D__ANDROID_COMMON_KERNEL__"
    # mediatek-bazel_defconfig firma con $(DEVICE_MODULES_REL_DIR)/certs/mtk_signing_key.pem;
    # usar la misma clave hace que el kernel confíe en los módulos stock (system_dlkm/vendor).
    DEVICE_MODULES_REL_DIR="$DM_DIR"
    LOCALVERSION="$LOCALVERSION_SUFFIX"
    -j"$JOBS"
)
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-build}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-a14xm}"

mkdir -p "$BUILD_OBJ" "$DIST"

FRAGMENTS=(
    "$KERNEL_DIR/arch/arm64/configs/gki_defconfig"
    "$DM_DIR/arch/arm64/configs/mediatek-bazel_defconfig"
    "$DM_DIR/kernel/configs/mt6833_overlay.config"
    "$DM_DIR/kernel/configs/S96901AA1.config"
    "$DM_DIR/kernel/configs/S96901AA1_debug.config"
)
[ "$KSU" = next ] && FRAGMENTS+=("$ROOT/scripts/configs/ksu.config")
[ -n "$EXTRA_CONFIG" ] && FRAGMENTS+=("$EXTRA_CONFIG")

log "Generando .config"
# -m: solo combinar; los símbolos de módulos externos (Kconfig.ext) se descartan,
# como en el Image GKI oficial, que no los compila dentro del kernel.
KCONFIG_CONFIG="$BUILD_OBJ/.config" \
    "$KERNEL_DIR/scripts/kconfig/merge_config.sh" -m -O "$BUILD_OBJ" "${FRAGMENTS[@]}" >/dev/null
make "${MAKE_ARGS[@]}" olddefconfig >/dev/null

check_cfg() { # símbolo valor_esperado
    local got
    got=$("$KERNEL_DIR/scripts/config" --file "$BUILD_OBJ/.config" --state "$1")
    [ "$got" = "$2" ] || die "CONFIG_$1=$got (se esperaba $2)"
}
check_cfg MODVERSIONS y
if [ "$KSU" = next ]; then
    check_cfg KSU y
    check_cfg KPROBES y
    check_cfg SECURITY_DEFEX n
fi

if [ "${CONFIG_ONLY:-0}" = 1 ]; then
    cp "$BUILD_OBJ/.config" "$DIST/kernel.config"
    log "CONFIG_ONLY=1: config generada en $DIST/kernel.config"
    exit 0
fi

# ------------------------------------------------------------------- build
log "Compilando Image con $JOBS hilos"
make "${MAKE_ARGS[@]}" Image Image.gz

cp "$BUILD_OBJ/arch/arm64/boot/Image" "$BUILD_OBJ/arch/arm64/boot/Image.gz" "$DIST/"
cp "$BUILD_OBJ/.config" "$DIST/kernel.config"
cp "$BUILD_OBJ/System.map" "$DIST/"
if command -v lz4 >/dev/null; then
    lz4 -f -l -12 --favor-decSpeed "$DIST/Image" "$DIST/Image.lz4" >/dev/null
fi

RELEASE=$(cat "$BUILD_OBJ/include/config/kernel.release")
echo "$RELEASE" > "$DIST/kernel.release"
log "Listo: $RELEASE"
ls -la "$DIST"
