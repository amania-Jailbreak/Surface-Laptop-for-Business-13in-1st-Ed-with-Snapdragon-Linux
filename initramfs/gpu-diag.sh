#!/bin/sh
# SPDX-License-Identifier: MIT

OUT=/gpu-diagnosis.txt
VFAT_MOUNT=/mnt/gpu-diag-vfat

save_to_vfat()
{
    selected=""
    fallback=""

    mkdir -p "$VFAT_MOUNT"

    for dev in \
        /dev/sd[a-z][0-9]* \
        /dev/mmcblk[0-9]p[0-9]* \
        /dev/nvme[0-9]n[0-9]p[0-9]*
    do
        [ -b "$dev" ] || continue

        info="$(blkid "$dev" 2>/dev/null)"
        case "$info" in
            *'TYPE="vfat"'*|*'TYPE="fat"'*|*'TYPE="msdos"'*)
                ;;
            *)
                continue
                ;;
        esac

        [ -n "$fallback" ] || fallback="$dev"

        umount "$VFAT_MOUNT" 2>/dev/null || true
        if ! mount -t vfat -o rw "$dev" "$VFAT_MOUNT" 2>/dev/null; then
            continue
        fi

        if [ -f "$VFAT_MOUNT/EFI/BOOT/BOOTAA64.EFI" ] ||
           [ -f "$VFAT_MOUNT/boot/Image-gpu-test" ]; then
            selected="$dev"
            break
        fi

        umount "$VFAT_MOUNT" 2>/dev/null || true
    done

    if [ -z "$selected" ] && [ -n "$fallback" ]; then
        if mount -t vfat -o rw "$fallback" "$VFAT_MOUNT" 2>/dev/null; then
            selected="$fallback"
        fi
    fi

    if [ -z "$selected" ]; then
        echo "No writable VFAT partition found"
        return 1
    fi

    target="$VFAT_MOUNT/gpu-diagnosis.txt"

    if cp "$OUT" "$target"; then
        sync
        echo "Saved a copy to $selected:/gpu-diagnosis.txt"
        umount "$VFAT_MOUNT"
        return 0
    fi

    echo "Failed to save the report to $selected"
    sync
    umount "$VFAT_MOUNT" 2>/dev/null || true
    return 1
}

mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true

{
    echo "========================================"
    echo " Surface GPU diagnostic"
    echo "========================================"
    echo

    echo "=== Kernel ==="
    uname -a
    echo

    echo "=== Device Tree status ==="
    for node in \
        /proc/device-tree/soc@0/gpu@3d00000 \
        /proc/device-tree/soc@0/gmu@3d6a000 \
        /proc/device-tree/soc@0/iommu@3da0000 \
        /proc/device-tree/soc@0/clock-controller@3d90000 \
        /proc/device-tree/soc@0/display-subsystem@ae00000 \
        /proc/device-tree/soc@0/display-subsystem@ae00000/displayport-controller@aea0000 \
        /proc/device-tree/soc@0/phy@aec5a00 \
        /proc/device-tree/soc@0/clock-controller@af00000
    do
        printf "%-55s " "$node"

        if [ ! -e "$node" ]; then
            echo "MISSING"
        elif [ -r "$node/status" ]; then
            tr -d '\000' < "$node/status"
            echo
        else
            echo "present, no status property"
        fi
    done
    echo

    echo "=== Platform bindings ==="
    for dev in \
        3d00000.gpu \
        3d6a000.gmu \
        3da0000.iommu \
        3d90000.clock-controller \
        ae00000.display-subsystem \
        ae01000.display-controller \
        aea0000.displayport-controller \
        aec5a00.phy \
        af00000.clock-controller
    do
        path="/sys/bus/platform/devices/$dev"
        printf "%-32s " "$dev"

        if [ ! -e "$path" ]; then
            echo "MISSING"
        elif [ -L "$path/driver" ]; then
            basename "$(readlink -f "$path/driver")"
        else
            echo "UNBOUND"
        fi
    done
    echo

    echo "=== Deferred probe reasons ==="
    if [ -r /sys/kernel/debug/devices_deferred ]; then
        grep -E \
            '3d00000|3d6a000|3da0000|3d90000|ae00000|ae01000|aea0000|aec5a00|af00000|gpu|gmu|adreno|mdss|dpu|displayport|edp' \
            /sys/kernel/debug/devices_deferred \
            || echo "No matching deferred devices"
    else
        echo "devices_deferred unavailable"
    fi
    echo

    echo "=== DRM connectors and modes ==="
    found_connector=0
    for connector in /sys/class/drm/card*-*; do
        [ -e "$connector" ] || continue
        found_connector=1
        echo "--- $(basename "$connector") ---"
        [ -r "$connector/status" ] && {
            printf "status: "
            cat "$connector/status"
        }
        [ -r "$connector/enabled" ] && {
            printf "enabled: "
            cat "$connector/enabled"
        }
        if [ -r "$connector/modes" ]; then
            echo "modes:"
            cat "$connector/modes"
        fi
    done
    [ "$found_connector" -eq 1 ] || echo "No DRM connectors found"
    echo

    echo "=== Backlight and PWM ==="
    if [ -d /sys/class/backlight ]; then
        for bl in /sys/class/backlight/*; do
            [ -e "$bl" ] || continue
            echo "--- $(basename "$bl") ---"
            for attr in brightness actual_brightness max_brightness bl_power; do
                [ -r "$bl/$attr" ] || continue
                printf "%s: " "$attr"
                cat "$bl/$attr"
            done
        done
    else
        echo "No backlight class"
    fi
    echo

    echo "=== Matching platform drivers ==="
    for drv in /sys/bus/platform/drivers/*; do
        [ -e "$drv" ] || continue

        name="$(basename "$drv")"
        echo "$name" |
            grep -Eiq 'gpu|gmu|adreno|msm|smmu' &&
            echo "$name"
    done
    echo

    echo "=== Firmware ==="
    FW=/lib/firmware/qcom/x1p42100/Microsoft/Surface12/qcdxkmsucpurwa.mbn

    if [ -r "$FW" ]; then
        ls -l "$FW"
    else
        echo "MISSING: $FW"
    fi
    echo

    echo "=== DRM device nodes ==="
    if [ -d /dev/dri ]; then
        ls -l /dev/dri
    else
        echo "/dev/dri does not exist"
    fi
    echo

    echo "=== DRM GPU smoke test ==="
    if [ -x /gpu-smoke ]; then
        /gpu-smoke
        echo "gpu-smoke exit status: $?"
    else
        echo "/gpu-smoke is missing"
    fi
    echo

    echo "=== GPU-related kernel configuration ==="
    if [ -r /proc/config.gz ]; then
        zcat /proc/config.gz 2>/dev/null |
            grep -E \
                'CONFIG_DRM_MSM|CONFIG_CLK_X1E80100_DISPCC|CONFIG_QCOM_QMP|CONFIG_ARM_SMMU|CONFIG_FW_LOADER'
    else
        echo "/proc/config.gz unavailable"
    fi
    echo

    echo "=== Relevant dmesg ==="
    dmesg |
        grep -Ei \
            '3d00000|3d6a000|3da0000|3d90000|ae00000|ae01000|aea0000|aec5a00|af00000|adreno|a6xx|gpu|gmu|drm|mdss|dpu|displayport|edp|panel|backlight|pwm|zap|firmware|smmu' |
        tail -n 250

} > "$OUT" 2>&1

cat "$OUT"

echo
echo "Saved to $OUT"

echo
echo "Searching for the boot VFAT partition..."
save_to_vfat
