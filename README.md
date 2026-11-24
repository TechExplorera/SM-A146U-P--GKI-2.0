# SM-A146U-P — GKI 2.0 (Galaxy A14 5G)

Código fuente stock de Samsung para el **Galaxy A14 5G (SM-A146U, `a14xm`, MediaTek MT6833)**. Incluye el kernel GKI **6.6.89 (android15-6.6, KMI 8)** y un sistema de compilación independiente para root con **SukiSU-Ultra** (modo LKM, por defecto) o **KernelSU-Next**.

| Ruta | Contenido |
|---|---|
| `kernel-6.6/` | Kernel GKI modificado por Samsung (genera el `Image` del boot) |
| `kernel/kernel_device_modules-6.6/` | Módulos y defconfigs de MediaTek/Samsung |
| `vendor/mediatek/` | Drivers externos de MediaTek (wifi, gpu, cámara…) |
| `build_kernel.sh` | Script original de Samsung (Kleaf/Bazel). No funciona solo, porque faltan `build/kernel`, `prebuilts/` y `external/` de AOSP. |
| `scripts/build_ksu.sh` | Script de compilación nuevo, basado en `make`, que no necesita Kleaf |
| `.github/workflows/build-kernel.yml` | CI que compila y empaqueta |

## Modos

| Modo | Qué genera | Qué flasheas | Kernel |
|---|---|---|---|
| **`sukisu` + `lkm`** (por defecto) | `android15-6.6_kernelsu.ko` compilado contra este árbol | Tu `boot`/`init_boot` **stock**, parcheado por el gestor SukiSU | Stock, sin cambios |
| `sukisu` o `next` + `builtin` | `Image` con KSU dentro y DEFEX apagado, zip AK3, `boot.tar` | Un `boot.img` con el kernel nuevo | Recompilado |
| `none` | `Image` stock recompilado | Nada (sirve como referencia) | Stock |

**Por qué un `.ko` propio en vez del genérico de SukiSU.** El LKM genérico se compila contra el GKI de Google. Este se compila contra el kernel modificado por Samsung, con su misma configuración, así que los CRC de los símbolos (MODVERSIONS) coinciden con los del kernel de tu teléfono. Además va firmado con la clave MTK que ese kernel ya trae en su keyring. El script comprueba con `check_symbol` que el módulo solo use símbolos que existen en este `vmlinux`.

## Compilar en GitHub Actions (recomendado)

1. Entra en **Actions → Build kernel / KernelSU → Run workflow**.
2. Deja `ksu = sukisu` y `ksu_mode = lkm`. En `ksu_ref` puedes poner otro tag o commit de SukiSU-Ultra; por defecto es `v3.0.0`.
3. Descarga el artefacto y saca `android15-6.6_kernelsu.ko`.

## Compilar en local

```bash
sudo apt install bc bison flex libssl-dev libelf-dev lz4 dwarves kmod git curl
```

```bash
mkdir -p ~/clang && curl -L "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-15.0.0_r1/clang-r510928.tar.gz" | tar xz -C ~/clang
```

```bash
CLANG_DIR=~/clang ./scripts/build_ksu.sh
```

El resultado queda en `out/dist/`.

| Variable | Valores |
|---|---|
| `KSU` | `sukisu` (por defecto), `next` o `none` |
| `KSU_MODE` | `lkm` o `builtin` |
| `KSU_REF` | tag o commit del repo de KSU |
| Otras | `JOBS=<n>`, `LOCALVERSION_SUFFIX=-x`, `EXTRA_CONFIG=<fragmento>`, `CONFIG_ONLY=1` |

## Instalar SukiSU en modo LKM

> ⚠️ Necesitas el **bootloader desbloqueado**. Desbloquearlo dispara Knox (e-fuse permanente), borra los datos y desactiva Samsung Pay, Secure Folder y similares. En variantes de operador de EE. UU. (SM-A146U) **es posible que no se pueda desbloquear**: comprueba que aparezca «Desbloqueo OEM» en Opciones de desarrollador.

1. Descarga el firmware **exacto** que tienes instalado y abre el `AP_*.tar.md5`.
   - Si trae `init_boot.img.lz4`, usa ese archivo.
   - Si no, usa `boot.img.lz4`.
   - Descomprímelo con `lz4 -d`.
2. Copia ese `.img` y `android15-6.6_kernelsu.ko` al teléfono.
3. Instala el **gestor SukiSU-Ultra** de la misma versión que el `ksu_ref` usado.
4. En el gestor: **Instalar → Seleccionar archivo** → elige el `.img` → como LKM elige **el archivo `.ko`** en lugar de un KMI de la lista.
5. El gestor guarda la imagen parcheada en *Descargas*.
6. En el PC, renómbralo a `init_boot.img` (o `boot.img`, según el que parcheaste) y empaquétalo para Odin:

```bash
tar -H ustar -cf ksu-patched.tar init_boot.img
```

7. Flashéalo con Odin en el slot **AP**.
8. Si falla la verificación AVB, flashea también un `vbmeta` con la verificación desactivada.

Para volver atrás, flashea el `.img` stock original con Odin.

**DEFEX en LKM.** En modo LKM el kernel es el stock, así que DEFEX sigue activo. Si alguna app no consigue root, usa el modo `builtin`, que lo desactiva.

## Qué cambia en modo builtin

Encima de la config oficial se aplica `scripts/configs/ksu.config`:

- `CONFIG_KSU=y`: KSU integrado, con hooks por kprobes y sin parches al código fuente.
- `CONFIG_SECURITY_DEFEX` desactivado.
- Los ganchos de `drivers/Kconfig` y `drivers/Makefile` se añaden solo durante la compilación y se retiran al terminar, así el árbol stock no cambia.

Para flashear: pasa `stock_boot_url` en el workflow y flashea el `boot.tar` resultante con Odin (AP). Otra opción es el zip AK3 con Kernel Flasher.
