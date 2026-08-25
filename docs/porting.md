# Porting checklist

For a new Linux distribution:

1. Use the pinned kernel source and config as a starting point.
2. Build the base DTB and select the Bluetooth overlay only when the UART
   wiring and firmware are present.
3. Keep the distribution's own initramfs generator, then add the early hook
   and matching modules.
4. Supply the real root UUID or label at UKI assembly time.
5. Keep the neutral `.osrel` metadata and use a distribution-specific boot
   entry outside this repository.
6. Run the full verification target and record hardware results in a release
   manifest.

Do not copy a full operating-system image into this repository. Record its
external name, version, retrieval location, and SHA256 in a separate release
note if a complete image is needed for testing.
