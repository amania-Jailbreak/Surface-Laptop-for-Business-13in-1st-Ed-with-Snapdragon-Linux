#!/bin/sh
set -eu

# The KVM GRUB entry arms next_entry=surface-el1-ready before Secure Launch.
# Clear it only after networking is up and KVM can create a VM. The ECV
# override alone does not prove that the kernel actually entered EL2.
case " $(cat /proc/cmdline) " in
    *' id_aa64mmfr0.ecv=1 '*) ;;
    *) exit 0 ;;
esac

command -v grub-editenv >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || {
    echo 'surface-kvm: python3 unavailable; retaining Ready fallback' >&2
    exit 0
}
if [ ! -c /dev/kvm ]; then
    modprobe kvm 2>/dev/null || true
fi
if ! python3 - <<'PY'
import fcntl
import os
import sys

try:
    kvm = os.open('/dev/kvm', os.O_RDWR | os.O_CLOEXEC)
    try:
        # Linux UAPI: KVM_GET_API_VERSION, KVM_CREATE_VM, KVM_API_VERSION.
        if fcntl.ioctl(kvm, 0xAE00, 0) != 12:
            raise RuntimeError('unsupported KVM API version')
        vm = fcntl.ioctl(kvm, 0xAE01, 0)
        os.close(vm)
    finally:
        os.close(kvm)
except (OSError, RuntimeError) as error:
    print(f'surface-kvm: KVM probe failed: {error}; retaining Ready fallback',
          file=sys.stderr)
    sys.exit(1)
PY
then
    exit 0
fi
grub-editenv /boot/grub/grubenv unset next_entry
echo 'surface-kvm: KVM VM creation succeeded; Ready fallback cleared'
