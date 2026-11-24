#!/usr/bin/env bash
# Compila el kernel GKI del Galaxy A14 5G (SM-A146U / a14xm, MT6833) desde el
# código stock de Samsung y genera KernelSU (SukiSU-Ultra o KernelSU-Next):
#
#   * Modo lkm     -> kernelsu.ko compilado contra ESTE árbol (mismo KMI/CRC que
#                     el kernel del teléfono). El kernel no se toca: el gestor
#                     parchea tu boot/init_boot stock con este .ko.
#   * Modo builtin -> KernelSU dentro del Image (+ DEFEX desactivado).
#
# Config igual que el build oficial (Kleaf/mgk, modo "user"):
#   gki_defconfig + mediatek-bazel_defconfig + mt6833_overlay + S96901AA1 + S96901AA1_debug
#
# Uso:
#   scripts/build_ksu.sh                          # SukiSU-Ultra, modo LKM (por defecto)
#   KSU=sukisu KSU_MODE=builtin scripts/build_ksu.sh
#   KSU=next scripts/build_ksu.sh                 # KernelSU-Next integrado
#   KSU=none scripts/build_ksu.sh                 # kernel stock sin root
#
# Variables:
#   KSU        sukisu | next | none           (por defecto: sukisu)
#   KSU_MODE   lkm | builtin                  (por defecto: lkm para sukisu, builtin para next)
#   KSU_REF    tag/commit del repo de KSU     (sukisu: v3.0.0, next: v3.4.2)
#   KSU_REPO   URL del repo (opcional, para forks)
#   CLANG_DIR  raíz de un Clang/LLVM (con bin/clang). Vacío = Clang del sistema.
#   JOBS       hilos de make                  (por defecto: nproc)
#   OUT_DIR    carpeta de salida              (por defecto: <repo>/out)
#   LOCALVERSION_SUFFIX  sufijo extra para uname -r (por defecto: vacío)
#   EXTRA_CONFIG  fragmento .config adicional opcional
#   CONFIG_ONLY=1 sólo genera y valida la .config, sin compilar

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="$ROOT/kernel-6.6"
DM_DIR="$ROOT/kernel/kernel_device_modules-6.6"
KMI="android15-6.6"

KSU="${KSU:-sukisu}"
case "$KSU" in
    sukisu)
        KSU_MODE="${KSU_MODE:-lkm}"
        KSU_REF="${KSU_REF:-v3.0.0}"
        KSU_REPO="${KSU_REPO:-https://github.com/SukiSU-Ultra/SukiSU-Ultra.git}"
        KSU_DIRNAME="SukiSU-Ultra"
        ;;
    next)
        KSU_MODE="${KSU_MODE:-builtin}"
        KSU_REF="${KSU_REF:-v3.4.2}"
        KSU_REPO="${KSU_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
        KSU_DIRNAME="KernelSU-Next"
        ;;
    none) KSU_MODE="none" ;;
    *) echo "KSU debe ser sukisu, next o none" >&2; exit 1 ;;
esac
case "$KSU_MODE" in lkm|builtin|none) ;; *) echo "KSU_MODE debe ser lkm o builtin" >&2; exit 1 ;; esac

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
log "Variante: KSU=$KSU modo=$KSU_MODE ${KSU_REF:+ref=$KSU_REF}"

# ------------------------------------------------------------ fuente de KSU
KSU_SRC=""
fetch_ksu() {
    KSU_SRC="$KERNEL_DIR/$KSU_DIRNAME"
    if [ ! -d "$KSU_SRC/.git" ]; then
        log "Clonando $KSU_DIRNAME"
        # Historial completo: el Kbuild de KSU calcula la versión con rev-list --count.
        git clone --quiet "$KSU_REPO" "$KSU_SRC"
    fi
    git -C "$KSU_SRC" fetch --quiet --tags origin
    git -C "$KSU_SRC" checkout --quiet "$KSU_REF"
    log "$KSU_DIRNAME en $(git -C "$KSU_SRC" describe --tags --always)"
}

# Ganchos en drivers/ sólo durante un build builtin; se retiran al salir para
# dejar el árbol stock intacto.
restore_hooks() {
    sed -i '/^obj-\$(CONFIG_KSU) += kernelsu\/$/d' "$KERNEL_DIR/drivers/Makefile"
    sed -i '/^source "drivers\/kernelsu\/Kconfig"$/d' "$KERNEL_DIR/drivers/Kconfig"
}
remove_builtin() {
    rm -f "$KERNEL_DIR/drivers/kernelsu"
    restore_hooks
}
setup_builtin() {
    # El enlace es relativo a drivers/: apunta a ../<repo>/kernel
    ln -sfn "../$KSU_DIRNAME/kernel" "$KERNEL_DIR/drivers/kernelsu"
    trap restore_hooks EXIT
    grep -q 'kernelsu/' "$KERNEL_DIR/drivers/Makefile" || \
        printf 'obj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_DIR/drivers/Makefile"
    grep -q 'drivers/kernelsu/Kconfig' "$KERNEL_DIR/drivers/Kconfig" || \
        sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig"
}

case "$KSU_MODE" in
    builtin) fetch_ksu; setup_builtin ;;
    lkm)     fetch_ksu; remove_builtin ;;   # el kernel queda stock
    none)    remove_builtin ;;
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
[ "$KSU_MODE" = builtin ] && FRAGMENTS+=("$ROOT/scripts/configs/ksu.config")
[ -n "$EXTRA_CONFIG" ] && FRAGMENTS+=("$EXTRA_CONFIG")

log "Generando .config"
# -m: sólo combinar; los símbolos de módulos externos (Kconfig.ext) se descartan,
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
check_cfg KPROBES y
case "$KSU_MODE" in
    builtin) check_cfg KSU y; check_cfg SECURITY_DEFEX n ;;
    *)       check_cfg KSU undef ;;
esac

if [ "${CONFIG_ONLY:-0}" = 1 ]; then
    cp "$BUILD_OBJ/.config" "$DIST/kernel.config"
    log "CONFIG_ONLY=1: config generada en $DIST/kernel.config"
    exit 0
fi

# ------------------------------------------------------------------- kernel
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

# ---------------------------------------------------------------------- LKM
if [ "$KSU_MODE" = lkm ]; then
    log "Compilando kernelsu.ko ($KSU_DIRNAME, LKM) contra este kernel"
    # Para un módulo externo, modpost necesita los CRC de vmlinux.
    cp "$BUILD_OBJ/vmlinux.symvers" "$BUILD_OBJ/Module.symvers"
    make "${MAKE_ARGS[@]}" modules_prepare >/dev/null

    KO_SRC="$KSU_SRC/kernel"
    # El LKM usa símbolos internos no exportados (path_umount, init_mm...): en el
    # teléfono ksuinit los resuelve con kallsyms antes de cargarlo. modpost sólo
    # debe avisar (el CI oficial de SukiSU parchea modpost para lo mismo);
    # check_symbol comprueba después que todos existen en este vmlinux.
    KSU_ARGS=(CONFIG_KSU=m KBUILD_MODPOST_WARN=1)
    [ "$KSU" = sukisu ] && KSU_ARGS+=(CONFIG_KPM=y)   # igual que los LKM oficiales de SukiSU

    make "${MAKE_ARGS[@]}" M="$KO_SRC" "${KSU_ARGS[@]}" clean >/dev/null 2>&1 || true
    make "${MAKE_ARGS[@]}" M="$KO_SRC" "${KSU_ARGS[@]}" modules

    KO="$DIST/${KMI}_kernelsu.ko"
    cp "$KO_SRC/kernelsu.ko" "$KO"
    llvm-strip -d "$KO"
    # ksuinit carga el LKM sin CRC de MODVERSIONS (el CI oficial parchea modpost
    # para no emitirlos); se vacía __versions para cumplir ese formato.
    : > "$BUILD_OBJ/empty"
    llvm-objcopy --update-section __versions="$BUILD_OBJ/empty" "$KO"

    # Sólo debe usar símbolos que exporta este vmlinux.
    if [ -f "$KO_SRC/tools/check_symbol.c" ]; then
        cc -O2 -o "$BUILD_OBJ/check_symbol" "$KO_SRC/tools/check_symbol.c"
        "$BUILD_OBJ/check_symbol" "$KO" "$BUILD_OBJ/vmlinux"
    fi

    # Firma con la misma clave MTK que el kernel lleva en su keyring.
    HASH=$("$KERNEL_DIR/scripts/config" --file "$BUILD_OBJ/.config" --state MODULE_SIG_HASH)
    "$BUILD_OBJ/scripts/sign-file" "$HASH" "$DM_DIR/certs/mtk_signing_key.pem" \
        "$BUILD_OBJ/certs/signing_key.x509" "$KO"

    VERMAGIC=$(grep -a -o -m1 'vermagic=[[:print:]]*' "$KO" || true)
    log "kernelsu.ko listo — vermagic: $VERMAGIC"
fi

log "Listo: $RELEASE"
ls -la "$DIST"
