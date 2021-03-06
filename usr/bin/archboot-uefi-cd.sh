#!/usr/bin/env bash
## Script for creating a UEFI CD bootable ISO from existing Archboot ISO
## by Tobias Powalowski <tpowa@archlinux.org>
## Contributed by "Keshav Padram Amburay" <the ddoott ridikulus ddoott rat aatt geemmayil ddoott ccoomm>
# change to english locale!
export LANG="en_US"

_BASENAME="$(basename "${0}")"

usage () {
    echo "${_BASENAME}: usage"
    echo "Create UEFI CD bootable ISO from existing Archboot ISO image."
    echo ""
    echo "PARAMETERS:"
    echo "  -i=IMAGENAME        Your input IMAGENAME."
    echo "  -o=IMAGENAME        Your output IMAGENAME."
    echo "  -h                  This message."
    exit 0
}

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
    case ${1} in
        -i=*|--i=*) INPUT_IMAGENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
        -o=*|--o=*) OUTPUT_IMAGENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
        -h|--h|?) usage ;; 
        *) usage ;;
        esac
    shift
done

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi

### check for available loop devices in a container
for i in $(seq 0 7); do
    ! [[ -e /dev/loop$i ]] && mknod /dev/loop$i b 7 $i
done
! [[ -e /dev/loop-control ]] && mknod /dev/loop-control c 10 237

ISOIMG=$(mktemp -d)
TEMP_DIR=$(mktemp -d)
FSIMG=$(mktemp -d)
MOUNT_FSIMG=$(mktemp -d)

## Extract old ISO
bsdtar -C "${ISOIMG}" -xf "${INPUT_IMAGENAME}"
# 7z x -o /tmp/ARCHBOOTISO/ "${INPUT_IMAGENAME}"

## Copy UEFI files
mkdir "${TEMP_DIR}"/boot
cp -r "${ISOIMG}"/{EFI,loader} "${TEMP_DIR}"/
cp "${ISOIMG}"/boot/vmlinuz_x86_64 "${TEMP_DIR}"/boot/
cp "${ISOIMG}"/boot/intel-ucode.img "${TEMP_DIR}"/boot/
cp "${ISOIMG}"/boot/initramfs_x86_64.img "${TEMP_DIR}"/boot/

## Delete IA32 UEFI files
rm -f "${TEMP_DIR}"/loader/*ia32*.conf
rm -rf "${TEMP_DIR}"/EFI/syslinux/efi32

## get size of boot x86_64 files
BOOTSIZE=$(du -bc ${TEMP_DIR} | grep total | cut -f1)
IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors

## Create cdefiboot.img
dd if=/dev/zero of="${FSIMG}"/cdefiboot.img bs="${IMGSZ}" count=1024 
mkfs.vfat "${FSIMG}"/cdefiboot.img
LOOPDEV="$(losetup --find --show "${FSIMG}"/cdefiboot.img)"

## Mount cdefiboot.img
mount -t vfat -o rw,users "${LOOPDEV}" "${MOUNT_FSIMG}"

## Copy all files from TEMP_DIR to MOUNT_FSIMG
# repeat all steps from above cp * is not working here!
mkdir "${MOUNT_FSIMG}"/boot
cp -r "${TEMP_DIR}"/{EFI,loader} "${MOUNT_FSIMG}"/
cp "${TEMP_DIR}"/boot/vmlinuz_x86_64 "${MOUNT_FSIMG}"/boot
cp "${TEMP_DIR}"/boot/intel-ucode.img "${MOUNT_FSIMG}"/boot
cp "${TEMP_DIR}"/boot/initramfs_x86_64.img "${MOUNT_FSIMG}"/boot

## Unmount cdefiboot.img
umount -d "${LOOPDEV}"
rm -rf "${MOUNT_FSIMG}"
rm -rf "${TEMP_DIR}"

## Move updated cdefiboot.img to old ISO extracted dir
mkdir -p "${ISOIMG}"/CDEFI/
rm "${ISOIMG}"/CDEFI/cdefiboot.img
mv "${FSIMG}"/cdefiboot.img "${ISOIMG}"/CDEFI/cdefiboot.img
rm -rf "${FSIMG}"

## Create new ISO with BIOS, ISOHYBRID and UEFI support
xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "ARCHBOOT" \
        -preparer "prepared by archboot-uefi-cd.sh" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e CDEFI/cdefiboot.img -isohybrid-gpt-basdat \
        -no-emul-boot \
        -isohybrid-mbr "${ISOIMG}"/boot/syslinux/isohdpfx.bin \
        -output "${OUTPUT_IMAGENAME}" "${ISOIMG}"/ &> /tmp/xorriso.log

if [[ -e "${OUTPUT_IMAGENAME}" ]]; then
    echo "Updated ISO at "${OUTPUT_IMAGENAME}""
else
    echo "ISO generation failed. See /tmp/xorriso.log for more info."
fi

## Delete old ISO extracted files
rm -rf "${ISOIMG}"
