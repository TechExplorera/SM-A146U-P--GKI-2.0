### AnyKernel3 — Galaxy A14 5G (SM-A146U / a14xm) GKI 6.6 + KernelSU-Next
## Basado en la plantilla de osm0sis @ xda-developers

### AnyKernel setup
properties() { '
kernel.string=A14 5G GKI 6.6 KernelSU-Next
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=a14xm
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# GKI: el boot sólo lleva el kernel; el ramdisk está en vendor_boot/init_boot.
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Sustituye únicamente el kernel, sin tocar el ramdisk.
split_boot;
flash_boot;
## end boot install
