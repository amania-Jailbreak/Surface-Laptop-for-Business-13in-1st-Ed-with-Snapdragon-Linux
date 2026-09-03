#!/bin/sh
set -eu

# The KVM GRUB entry arms next_entry=surface-el1-ready before Secure Launch.
# Clear it only after the EL2 kernel has reached network-online.target.  If
# slbounce, the TCB, the DTB, or the kernel fails earlier, GRUB retains the
# ready entry for the next power cycle.
case " $(cat /proc/cmdline) " in
    *' id_aa64mmfr0.ecv=1 '*) ;;
    *) exit 0 ;;
esac

command -v grub-editenv >/dev/null 2>&1 || exit 0
grub-editenv /boot/grub/grubenv unset next_entry
