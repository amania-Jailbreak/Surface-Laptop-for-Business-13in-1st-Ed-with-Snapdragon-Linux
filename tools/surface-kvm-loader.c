// SPDX-License-Identifier: BSD-2-Clause
/*
 * Small EFI launcher for the Surface EL2/KVM boot path.
 *
 * The normal Proxmox shim is kept as shimaa64.efi. Loading slbounce before
 * starting it lets slbounce hook ExitBootServices(), after GRUB has installed
 * the selected EL2 device tree. qebspil is optional and is loaded first when
 * this file is built with SURFACE_KVM_LOAD_QEBSPIL.
 */

#include <efi.h>
#include <efilib.h>

static EFI_STATUS start_image_from_volume(EFI_HANDLE parent,
					  EFI_HANDLE device,
					  CHAR16 *filename)
{
	EFI_DEVICE_PATH *path;
	EFI_HANDLE child = NULL;
	EFI_STATUS status;
	UINTN exit_data_size = 0;
	CHAR16 *exit_data = NULL;

	path = FileDevicePath(device, filename);
	if (!path)
		return EFI_OUT_OF_RESOURCES;

	status = uefi_call_wrapper(BS->LoadImage, 6, FALSE, parent, path,
					   NULL, 0, &child);
	FreePool(path);
	if (EFI_ERROR(status))
		return status;

	status = uefi_call_wrapper(BS->StartImage, 3, child,
					   &exit_data_size, &exit_data);
	if (exit_data) {
		Print(L"%s\n", exit_data);
		FreePool(exit_data);
	}

	if (EFI_ERROR(status))
		uefi_call_wrapper(BS->UnloadImage, 1, child);

	return status;
}

EFI_STATUS efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *system_table)
{
	EFI_GUID loaded_image_guid = LOADED_IMAGE_PROTOCOL;
	EFI_LOADED_IMAGE *loaded_image = NULL;
	EFI_STATUS status;

	InitializeLib(image, system_table);

	status = uefi_call_wrapper(BS->HandleProtocol, 3, image,
					   &loaded_image_guid,
					   (VOID **)&loaded_image);
	if (EFI_ERROR(status) || !loaded_image) {
		Print(L"surface-kvm: cannot locate the boot volume: %r\n", status);
		return EFI_ERROR(status) ? status : EFI_NOT_FOUND;
	}

#ifdef SURFACE_KVM_LOAD_QEBSPIL
	Print(L"surface-kvm: loading qebspil...\n");
	status = start_image_from_volume(image, loaded_image->DeviceHandle,
					 L"\\EFI\\BOOT\\qebspilaa64.efi");
	if (EFI_ERROR(status)) {
		Print(L"surface-kvm: qebspil failed: %r\n", status);
		return status;
	}
#endif

	Print(L"surface-kvm: loading Secure Launch driver...\n");
	status = start_image_from_volume(image, loaded_image->DeviceHandle,
					 L"\\EFI\\BOOT\\slbounceaa64.efi");
	if (EFI_ERROR(status)) {
		Print(L"surface-kvm: slbounce failed: %r\n", status);
		Print(L"surface-kvm: check tcblaunch.exe and Secure Boot state.\n");
		return status;
	}

	Print(L"surface-kvm: Secure Launch hook installed; starting Proxmox...\n");
	status = start_image_from_volume(image, loaded_image->DeviceHandle,
					 L"\\EFI\\BOOT\\shimaa64.efi");
	if (EFI_ERROR(status))
		Print(L"surface-kvm: Proxmox shim failed: %r\n", status);

	return status;
}
