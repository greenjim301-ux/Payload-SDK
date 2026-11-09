#!/bin/bash
###
# DJI PSDK USB Bulk Gadget Startup Script for RK3568
###

set -e

GADGET_DIR=/sys/kernel/config/usb_gadget/dji_bulk
STARTUP_BULK_BIN=/usr/local/bin/startup_bulk

start_gadget() {
    echo "Starting DJI USB Bulk Gadget..."

    # Ensure required modules are loaded
    modprobe configfs 2>/dev/null || true
    modprobe libcomposite 2>/dev/null || true
    modprobe usb_f_fs 2>/dev/null || true

    # Mount configfs if not mounted
    if ! mountpoint -q /sys/kernel/config; then
        mount -t configfs none /sys/kernel/config
    fi

    # Kill old startup_bulk instances if running
    killall startup_bulk 2>/dev/null || true

    # Clean existing gadget if exists
    if [ -d "$GADGET_DIR" ]; then
        echo "" > "$GADGET_DIR/UDC" 2>/dev/null || true
        rm -f "$GADGET_DIR/configs/c.1/ffs.bulk1" 2>/dev/null || true
        rm -f "$GADGET_DIR/configs/c.1/ffs.bulk2" 2>/dev/null || true
        rmdir "$GADGET_DIR/configs/c.1/strings/0x409" 2>/dev/null || true
        rmdir "$GADGET_DIR/configs/c.1" 2>/dev/null || true
        rmdir "$GADGET_DIR/functions/ffs.bulk1" 2>/dev/null || true
        rmdir "$GADGET_DIR/functions/ffs.bulk2" 2>/dev/null || true
        rmdir "$GADGET_DIR/strings/0x409" 2>/dev/null || true
        rmdir "$GADGET_DIR" 2>/dev/null || true
    fi

    # Create gadget structure
    mkdir -p "$GADGET_DIR"
    cd "$GADGET_DIR"

    echo 0x2CA3 > idVendor
    echo 0xF001 > idProduct
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB

    echo 0xEF > bDeviceClass
    echo 0x02 > bDeviceSubClass
    echo 0x01 > bDeviceProtocol

    mkdir -p strings/0x409
    echo "0123456789ABCDEF" > strings/0x409/serialnumber
    echo "DJI" > strings/0x409/manufacturer
    echo "PSDK USB BULK" > strings/0x409/product

    # Create configuration
    mkdir -p configs/c.1
    mkdir -p configs/c.1/strings/0x409
    echo "DJI Bulk Config" > configs/c.1/strings/0x409/configuration
    echo 500 > configs/c.1/MaxPower

    # Create FunctionFS instances
    mkdir -p functions/ffs.bulk1
    mkdir -p functions/ffs.bulk2
    ln -sf functions/ffs.bulk1 configs/c.1/
    ln -sf functions/ffs.bulk2 configs/c.1/

    # Mount FunctionFS
    mkdir -p /dev/usb-ffs/bulk1 /dev/usb-ffs/bulk2
    umount /dev/usb-ffs/bulk1 2>/dev/null || true
    umount /dev/usb-ffs/bulk2 2>/dev/null || true
    mount -t functionfs bulk1 /dev/usb-ffs/bulk1
    mount -t functionfs bulk2 /dev/usb-ffs/bulk2

    # Launch startup_bulk daemon to write descriptors to ep0
    if [ -x "$STARTUP_BULK_BIN" ]; then
        "$STARTUP_BULK_BIN" /dev/usb-ffs/bulk1 &
        sleep 1
        "$STARTUP_BULK_BIN" /dev/usb-ffs/bulk2 &
        sleep 1
    else
        echo "Error: $STARTUP_BULK_BIN not found or not executable!"
        exit 1
    fi

    # Bind to physical UDC
    UDC_NAME=$(ls /sys/class/udc | head -n 1)
    if [ -z "$UDC_NAME" ]; then
        echo "Error: No UDC device found in /sys/class/udc!"
        exit 1
    fi

    echo "$UDC_NAME" > UDC
    echo "DJI USB Bulk Gadget successfully initialized and bound to $UDC_NAME."
}

stop_gadget() {
    echo "Stopping DJI USB Bulk Gadget..."
    if [ -d "$GADGET_DIR" ]; then
        echo "" > "$GADGET_DIR/UDC" 2>/dev/null || true
    fi

    killall startup_bulk 2>/dev/null || true
    sleep 1

    umount /dev/usb-ffs/bulk1 2>/dev/null || true
    umount /dev/usb-ffs/bulk2 2>/dev/null || true

    if [ -d "$GADGET_DIR" ]; then
        rm -f "$GADGET_DIR/configs/c.1/ffs.bulk1" 2>/dev/null || true
        rm -f "$GADGET_DIR/configs/c.1/ffs.bulk2" 2>/dev/null || true
        rmdir "$GADGET_DIR/configs/c.1/strings/0x409" 2>/dev/null || true
        rmdir "$GADGET_DIR/configs/c.1" 2>/dev/null || true
        rmdir "$GADGET_DIR/functions/ffs.bulk1" 2>/dev/null || true
        rmdir "$GADGET_DIR/functions/ffs.bulk2" 2>/dev/null || true
        rmdir "$GADGET_DIR/strings/0x409" 2>/dev/null || true
        rmdir "$GADGET_DIR" 2>/dev/null || true
    fi
    echo "DJI USB Bulk Gadget stopped."
}

case "$1" in
    start)
        start_gadget
        ;;
    stop)
        stop_gadget
        ;;
    restart)
        stop_gadget
        start_gadget
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
