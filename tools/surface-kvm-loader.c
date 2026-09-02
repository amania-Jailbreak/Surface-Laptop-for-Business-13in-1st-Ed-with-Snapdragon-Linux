// SPDX-License-Identifier: BSD-2-Clause
/*
 * Small EFI launcher for the Surface EL2/KVM boot path.
 *
 * The normal Proxmox shim is kept as shimaa64.efi. The EL2 variant installs
 * the EL2 device tree, then loads slbounce before starting either a standalone
 * installer GRUB or the normal shim. qebspil is optional and is loaded first
 * when this file is built with SURFACE_KVM_LOAD_QEBSPIL.
 */

#include <efi.h>
#include <efilib.h>

static CHAR16 ascii_lower(CHAR16 character)
{
	if (character >= L'A' && character <= L'Z')
		return character + (L'a' - L'A');
	return character;
}

static BOOLEAN path_contains(EFI_DEVICE_PATH *path, CHAR16 *needle)
{
	CHAR16 *text;
	CHAR16 *candidate;
	CHAR16 *left;
	CHAR16 *right;
	BOOLEAN found = FALSE;

	if (!path || !needle || !needle[0])
		return FALSE;
	text = DevicePathToStr(path);
	if (!text)
		return FALSE;

	for (candidate = text; *candidate && !found; candidate++) {
		left = candidate;
		right = needle;
		while (*left && *right &&
		       ascii_lower(*left) == ascii_lower(*right)) {
			left++;
			right++;
		}
		found = (*right == L'\0');
	}

	FreePool(text);
	return found;
}

/*
 * Keep the last EFI stage on the ESP.  This is intentionally best-effort:
 * the marker is only a diagnostic aid and must never prevent normal boot.
 */
static void write_state(EFI_HANDLE device, CHAR8 *state)
{
	EFI_GUID fs_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
	EFI_FILE_IO_INTERFACE *io = NULL;
	EFI_FILE_HANDLE volume = NULL;
	EFI_FILE_HANDLE file = NULL;
	EFI_STATUS status;
	UINTN size;
	CHAR8 buffer[64];

	status = uefi_call_wrapper(BS->HandleProtocol, 3, device, &fs_guid,
					   (VOID **)&io);
	if (EFI_ERROR(status) || !io)
		return;

	status = uefi_call_wrapper(io->OpenVolume, 2, io, &volume);
	if (EFI_ERROR(status) || !volume)
		return;

	status = uefi_call_wrapper(volume->Open, 5, volume, &file,
					   L"\\surface-kvm-loader.state",
					   EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE |
						   EFI_FILE_MODE_CREATE,
					   EFI_FILE_ARCHIVE);
	if (!EFI_ERROR(status) && file) {
		uefi_call_wrapper(file->SetPosition, 2, file, 0);
		ZeroMem(buffer, sizeof(buffer));
		size = 0;
		while (state[size] != '\0' && size < sizeof(buffer) - 1) {
			buffer[size] = state[size];
			size++;
		}
		size = sizeof(buffer);
		uefi_call_wrapper(file->Write, 3, file, &size, buffer);
		uefi_call_wrapper(file->Flush, 1, file);
		uefi_call_wrapper(file->Close, 1, file);
	}

	uefi_call_wrapper(volume->Close, 1, volume);
}

#ifdef SURFACE_KVM_INSTALL_DTB
static EFI_STATUS install_el2_dtb(EFI_HANDLE device)
{
	EFI_GUID fs_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
	EFI_GUID dtb_guid = EFI_DTB_TABLE_GUID;
	EFI_FILE_IO_INTERFACE *io = NULL;
	EFI_FILE_HANDLE volume = NULL;
	EFI_FILE_HANDLE file = NULL;
	EFI_FILE_INFO *info = NULL;
	EFI_PHYSICAL_ADDRESS dtb_phys = 0;
	EFI_STATUS status;
	UINT64 dtb_size;
	UINTN pages;
	UINTN read_size;

	status = uefi_call_wrapper(BS->HandleProtocol, 3, device, &fs_guid,
					   (VOID **)&io);
	if (EFI_ERROR(status) || !io)
		return EFI_NOT_FOUND;
	status = uefi_call_wrapper(io->OpenVolume, 2, io, &volume);
	if (EFI_ERROR(status) || !volume)
		return status;

	status = uefi_call_wrapper(volume->Open, 5, volume, &file,
					   L"\\surface-laptop-13-el2.dtb",
					   EFI_FILE_MODE_READ, 0);
	if (EFI_ERROR(status) || !file)
		goto out;

	info = LibFileInfo(file);
	if (!info) {
		status = EFI_DEVICE_ERROR;
		goto out;
	}
	dtb_size = info->FileSize;
	FreePool(info);
	info = NULL;
	if (!dtb_size || dtb_size > 1024 * 1024) {
		status = EFI_BAD_BUFFER_SIZE;
		goto out;
	}

	pages = (UINTN)((dtb_size + 4095) / 4096);
	status = uefi_call_wrapper(BS->AllocatePages, 4, AllocateAnyPages,
					   EfiACPIReclaimMemory, pages, &dtb_phys);
	if (EFI_ERROR(status))
		goto out;

	read_size = (UINTN)dtb_size;
	status = uefi_call_wrapper(file->Read, 3, file, &read_size,
					   (VOID *)(UINTN)dtb_phys);
	if (EFI_ERROR(status) || read_size != (UINTN)dtb_size) {
		if (!EFI_ERROR(status))
			status = EFI_DEVICE_ERROR;
		uefi_call_wrapper(BS->FreePages, 2, dtb_phys, pages);
		dtb_phys = 0;
		goto out;
	}

	status = uefi_call_wrapper(BS->InstallConfigurationTable, 2, &dtb_guid,
					   (VOID *)(UINTN)dtb_phys);
	if (EFI_ERROR(status))
		uefi_call_wrapper(BS->FreePages, 2, dtb_phys, pages);

out:
	if (info)
		FreePool(info);
	if (file)
		uefi_call_wrapper(file->Close, 1, file);
	if (volume)
		uefi_call_wrapper(volume->Close, 1, volume);
	return status;
}
#endif

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
	write_state(loaded_image->DeviceHandle, (CHAR8 *)"launcher-start\n");

#ifdef SURFACE_KVM_INSTALL_DTB
	write_state(loaded_image->DeviceHandle, (CHAR8 *)"dtb-start\n");
	status = install_el2_dtb(loaded_image->DeviceHandle);
	if (EFI_ERROR(status)) {
		write_state(loaded_image->DeviceHandle, (CHAR8 *)"dtb-fail\n");
		Print(L"surface-kvm: EL2 DTB install failed: %r\n", status);
		return status;
	}
	write_state(loaded_image->DeviceHandle, (CHAR8 *)"dtb-ok\n");
#endif

#ifdef SURFACE_KVM_LOAD_QEBSPIL
	write_state(loaded_image->DeviceHandle, (CHAR8 *)"qebspil-start\n");
	Print(L"surface-kvm: loading qebspil...\n");
	status = start_image_from_volume(image, loaded_image->DeviceHandle,
					 L"\\EFI\\BOOT\\qebspilaa64.efi");
	if (EFI_ERROR(status)) {
		write_state(loaded_image->DeviceHandle, (CHAR8 *)"qebspil-fail\n");
		Print(L"surface-kvm: qebspil failed: %r\n", status);
		return status;
	}
	write_state(loaded_image->DeviceHandle, (CHAR8 *)"qebspil-ok\n");
#endif

	write_state(loaded_image->DeviceHandle, (CHAR8 *)"slbounce-start\n");
	Print(L"surface-kvm: loading Secure Launch driver...\n");
	status = start_image_from_volume(image, loaded_image->DeviceHandle,
					 L"\\EFI\\BOOT\\slbounceaa64.efi");
	if (EFI_ERROR(status)) {
		write_state(loaded_image->DeviceHandle, (CHAR8 *)"slbounce-fail\n");
		Print(L"surface-kvm: slbounce failed: %r\n", status);
		Print(L"surface-kvm: check tcblaunch.exe and Secure Boot state.\n");
		return status;
	}
	write_state(loaded_image->DeviceHandle, (CHAR8 *)"slbounce-ok\n");

	/*
	 * An installer ISO cannot persist GRUB's next_entry in its read-only
	 * filesystem.  The ISO builder therefore places a standalone GRUB image
	 * here.  Installed systems do not have that file and continue through the
	 * normal shim, which consumes the next_entry written by the outer GRUB
	 * menu entry.
	 */
	write_state(loaded_image->DeviceHandle, (CHAR8 *)"grub-start\n");
	Print(L"surface-kvm: Secure Launch hook installed; looking for KVM GRUB...\n");
	CHAR16 *grub_filename = L"\\EFI\\BOOT\\surface-kvm-grubaa64.efi";
	if (path_contains(loaded_image->FilePath, L"surface-kvm-entry-terminal"))
		grub_filename = L"\\EFI\\BOOT\\surface-kvm-grub-terminal.efi";
	status = start_image_from_volume(image, loaded_image->DeviceHandle,
					 grub_filename);
	if (status == EFI_NOT_FOUND) {
		write_state(loaded_image->DeviceHandle, (CHAR8 *)"shim-start\n");
		Print(L"surface-kvm: KVM GRUB not present; starting Proxmox shim...\n");
		status = start_image_from_volume(image, loaded_image->DeviceHandle,
					 L"\\EFI\\BOOT\\shimaa64.efi");
	}
	if (EFI_ERROR(status)) {
		write_state(loaded_image->DeviceHandle, (CHAR8 *)"next-stage-fail\n");
		Print(L"surface-kvm: next boot stage failed: %r\n", status);
	} else {
		write_state(loaded_image->DeviceHandle, (CHAR8 *)"next-stage-ok\n");
	}

	return status;
}
