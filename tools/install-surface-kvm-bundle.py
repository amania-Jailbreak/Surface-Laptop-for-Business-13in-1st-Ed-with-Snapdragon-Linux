#!/usr/bin/env python3
"""Install a verified Ready-based KVM bundle on the Surface, without rebooting.

Run on the target as root: python3 install-surface-kvm-bundle.py BUNDLE
The caller transfers the bundle via SSH. Existing Ready boot components are
checked and preserved; every overwritten file is backed up on the rootfs.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    if os.geteuid() or len(sys.argv) != 2:
        raise RuntimeError('Run as root with exactly one bundle directory')
    bundle = Path(sys.argv[1]).resolve()
    manifest = {}
    for line in (bundle / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_.-]+)', line)
        if not match or match[2] in manifest or match[2] in ('.', '..'):
            raise RuntimeError('Invalid bundle SHA256SUMS')
        manifest[match[2]] = match[1]
        if (bundle / match[2]).is_symlink() or digest(bundle / match[2]) != match[1]:
            raise RuntimeError(f'Bundle hash mismatch: {match[2]}')
    provenance = json.loads((bundle / 'provenance.json').read_text())
    version = provenance['kernel_version']
    if not re.fullmatch(r'[A-Za-z0-9_.+-]+', version) or run('uname', '-r') != version:
        raise RuntimeError('Ready kernel version changed')
    ready = {
        f'/boot/vmlinuz-{version}': provenance['ready_kernel_sha256'],
        f'/boot/initrd.img-{version}': provenance['ready_initrd_sha256'],
        '/boot/surface-laptop-13.dtb': provenance['ready_dtb_sha256'],
    }
    for path, expected in ready.items():
        if digest(path) != expected:
            raise RuntimeError(f'Ready input changed: {path}')
    if digest(bundle / 'surface-kvm-linux') != provenance['ready_kernel_sha256']:
        raise RuntimeError('This installer requires the verified Ready kernel')
    if run('findmnt', '-n', '-o', 'FSTYPE', '--target', '/boot/efi') != 'vfat':
        raise RuntimeError('ESP is not mounted as vfat')
    esp = run('findmnt', '-n', '-o', 'SOURCE', '--target', '/boot/efi')
    if run('blkid', '-s', 'UUID', '-o', 'value', esp) != '584B-B4D4':
        raise RuntimeError('Wrong ESP UUID')
    if run('findmnt', '-n', '-o', 'UUID', '--target', '/') != 'f621d247-7647-4244-aad3-1fffe95afe92':
        raise RuntimeError('Wrong Ready root UUID')
    if shutil.disk_usage('/boot/efi').free < 128 * 1024 * 1024:
        raise RuntimeError('Insufficient ESP staging space')
    contents = run('lsinitramfs', str(bundle / 'surface-kvm-initrd.img'))
    versions = set(re.findall(r'(?:^|/)lib/modules/([^/\n]+)', contents))
    if versions != {version} or 'init' not in contents.splitlines():
        raise RuntimeError(f'initramfs version/content mismatch: {versions}')
    run('grub-script-check', str(bundle / 'surface-kvm-grubaa64.cfg'))
    mapping = {
        'surface-kvm-linux': ['boot/efi/EFI/BOOT/surface-kvm-linux', 'boot/efi/surface-kvm-linux', f'boot/vmlinuz-{version}-kvm'],
        'surface-kvm-initrd.img': ['boot/efi/EFI/BOOT/surface-kvm-initrd.img', 'boot/efi/surface-kvm-initrd.img', f'boot/initrd.img-{version}-kvm'],
        'surface-laptop-13-el2.dtb': ['boot/efi/EFI/BOOT/surface-laptop-13-el2.dtb', 'boot/efi/surface-laptop-13-el2.dtb', 'boot/surface-laptop-13-el2.dtb'],
        'surface-kvm-entry.efi': ['boot/efi/EFI/BOOT/surface-kvm-entry.efi', 'boot/efi/EFI/BOOT/surface-kvm-entry-terminal.efi', 'boot/efi/EFI/proxmox/surface-kvm-entry.efi'],
        'surface-kvm-grubaa64.efi': ['boot/efi/EFI/BOOT/surface-kvm-grubaa64.efi', 'boot/efi/EFI/BOOT/surface-kvm-grub-terminal.efi'],
        'surface-kvm-grubaa64.cfg': ['boot/efi/EFI/BOOT/surface-kvm-grubaa64.cfg'],
        'slbounceaa64.efi': ['boot/efi/EFI/BOOT/slbounceaa64.efi'],
        'tcblaunch.exe': ['boot/efi/tcblaunch.exe'],
        'grub.cfg': ['boot/efi/EFI/BOOT/grub.cfg', 'boot/efi/EFI/proxmox/grub.cfg'],
        'installed-grub-surface-laptop-13': ['etc/grub.d/01_surface-laptop-13'],
        'surface-kvm-clear-fallback.sh': ['usr/local/sbin/surface-kvm-clear-fallback'],
        'surface-kvm-clear-fallback.service': ['etc/systemd/system/surface-kvm-clear-fallback.service'],
    }
    for optional, destination in [('startup.nsh', 'boot/efi/startup.nsh'),
                                  ('surface-kvm-shell-bridge.efi', 'boot/efi/EFI/BOOT/surface-kvm-shell-bridge.efi')]:
        if optional in manifest:
            mapping[optional] = [destination]
    if not set(mapping).issubset(manifest) or 'provenance.json' not in manifest:
        raise RuntimeError('Missing manifest entries')
    if manifest['tcblaunch.exe'] != '5dfcd0253b6ee99499ab33cac221e8a9cea47f3fdf6d4e11de9a9f3c4770d03d':
        raise RuntimeError('Unexpected TCB')
    protected = list(ready) + ['/boot/efi/EFI/BOOT/BOOTAA64.EFI',
        '/boot/efi/EFI/BOOT/shimaa64.efi', '/boot/efi/EFI/BOOT/grubaa64.efi',
        '/boot/efi/EFI/proxmox/shimaa64.efi', '/boot/efi/EFI/proxmox/grubaa64.efi']
    protected_hashes = {path: digest(path) for path in protected}
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path('/var/backups/surface-kvm') / stamp
    backup.mkdir(parents=True)
    destinations = [p for paths in mapping.values() for p in paths]
    for path in destinations + ['boot/grub/grub.cfg', 'boot/grub/grubenv', 'etc/default/grub']:
        source = Path('/') / path
        if source.is_file():
            target = backup / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    (backup / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(f'Backup: {backup}', flush=True)
    for source, paths in mapping.items():
        for path in paths:
            destination = Path('/') / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + '.kvm-new')
            shutil.copyfile(bundle / source, temporary)
            temporary.chmod(0o755 if path.startswith(('etc/grub.d/', 'usr/local/sbin/')) else 0o644)
            with temporary.open('rb') as stream:
                os.fsync(stream.fileno())
            if digest(temporary) != manifest[source]:
                raise RuntimeError(f'Staged hash mismatch: {temporary}')
            os.replace(temporary, destination)
    run('update-grub')
    run('grub-script-check', '/boot/grub/grub.cfg')
    run('systemctl', 'daemon-reload')
    run('systemctl', 'reenable', 'surface-kvm-clear-fallback.service')
    os.sync()
    report = []
    for source, paths in mapping.items():
        for path in paths:
            destination = Path('/') / path
            actual = digest(destination)
            if actual != manifest[source]:
                raise RuntimeError(f'Deployed hash mismatch: {destination}')
            stat = destination.stat()
            report.append({'path': str(destination), 'sha256': actual,
                           'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns})
    for path, expected in protected_hashes.items():
        if digest(path) != expected:
            raise RuntimeError(f'Protected Ready component changed: {path}')
    (backup / 'deployed.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    print('Ready components unchanged; hashes verified. No reboot or default change performed.')
    subprocess.run(['efibootmgr', '-v'], check=False)


if __name__ == '__main__':
    main()
