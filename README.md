# SM-A146U-P — GKI 2.0 (Galaxy A14 5G)

Código fuente stock de Samsung para el **Galaxy A14 5G (SM-A146U, `a14xm`, MediaTek MT6833)**. Incluye el kernel GKI **6.6.89 (android15-6.6, KMI 8)** y un sistema de compilación independiente que integra **KernelSU-Next**.

| Ruta | Contenido |
|---|---|
| `kernel-6.6/` | Kernel GKI modificado por Samsung (genera el `Image` del boot) |
| `kernel/kernel_device_modules-6.6/` | Módulos y defconfigs de MediaTek/Samsung |
| `vendor/mediatek/` | Drivers externos de MediaTek (wifi, gpu, cámara…) |
| `build_kernel.sh` | Script original de Samsung (Kleaf/Bazel). No funciona solo, porque faltan `build/kernel`, `prebuilts/` y `external/` de AOSP. |
| `scripts/build_ksu.sh` | Script de compilación nuevo, basado en `make`, que no necesita Kleaf |
| `.github/workflows/build-kernel.yml` | CI que compila y empaqueta el kernel |

## Compilar en GitHub Actions (recomendado)

1. Entra en **Actions → Build kernel (KernelSU-Next) → Run workflow**.
2. Opciones:
   - `ksu`: `next` para KernelSU-Next, `none` para el kernel stock.
   - `ksu_ref`: tag de KernelSU-Next (por defecto `v3.4.2`).
   - `stock_boot_url` (opcional): URL directa al `boot.img` o `boot.img.lz4` **de tu misma versión de firmware**. Con ella el workflow genera también `boot.img` y `boot.tar` para Odin.
3. Descarga el artefacto, que contiene:
   - `Image`, `Image.gz` e `Image.lz4`: el kernel.
   - `AK3-a14xm-*.zip`: para Kernel Flasher o un recovery personalizado.
   - `boot.img` y `boot.tar`: solo si indicaste `stock_boot_url`.
   - `kernel.config`: la configuración final.

## Compilar en local

```bash
sudo apt install bc bison flex libssl-dev libelf-dev lz4 dwarves git curl
```

```bash
mkdir -p ~/clang && curl -L "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-15.0.0_r1/clang-r510928.tar.gz" | tar xz -C ~/clang
```

```bash
CLANG_DIR=~/clang ./scripts/build_ksu.sh
```

El resultado queda en `out/dist/`. Variables útiles: `KSU=none`, `KSU_REF=<tag>`, `JOBS=<n>`, `LOCALVERSION_SUFFIX=-ksun`, `EXTRA_CONFIG=<fragmento>` y `CONFIG_ONLY=1`.

## Qué cambia respecto al stock

La configuración se arma igual que en el build oficial en modo *user*: `gki_defconfig` + `mediatek-bazel_defconfig` + `mt6833_overlay` + `S96901AA1` + `S96901AA1_debug`. Encima se aplica `scripts/configs/ksu.config`:

- `CONFIG_KSU=y`: KernelSU-Next integrado. Usa hooks por kprobes y no parchea el código fuente.
- `CONFIG_SECURITY_DEFEX` desactivado. Es la protección de Samsung que mata los procesos root lanzados desde apps.

Los módulos se firman con la misma clave MTK que usa el build oficial (`certs/mtk_signing_key.pem`), así que el kernel acepta los módulos stock de `vendor_boot`, `vendor_dlkm` y `system_dlkm`.

SUSFS no se parchea en el kernel: KernelSU-Next v3.x lo distribuye como módulo (LKM) aparte.

## Instalación (bajo tu responsabilidad)

> ⚠️ Necesitas el **bootloader desbloqueado**. Desbloquearlo dispara Knox (e-fuse permanente), borra los datos y desactiva Samsung Pay, Secure Folder y similares. En variantes de operador de EE. UU. (SM-A146U) **es posible que no se pueda desbloquear**: comprueba que aparezca «Desbloqueo OEM» en Opciones de desarrollador. Haz copia de tu `boot.img` stock antes de flashear.

1. Saca `boot.img.lz4` del `AP_*.tar.md5` de **tu firmware exacto** y súbelo a una URL directa. Pásala como `stock_boot_url`.
2. Flashea `boot.tar` con Odin en el slot **AP**.
3. Si el teléfono rechaza el boot por AVB, flashea también un `vbmeta` con la verificación desactivada.
4. Instala la app **KernelSU-Next Manager** de la misma versión que `ksu_ref`.

Si no arranca, vuelve a flashear tu `boot.img` stock con Odin.

## Alternativa sin compilar

KernelSU-Next también funciona en **modo LKM**: la app parchea tu `boot.img` stock sin compilar ningún kernel. Si solo quieres root, prueba eso primero. Este kernel tiene sentido si quieres KSU integrado, DEFEX apagado o hacer otros cambios al kernel.
