# Device-tree sources

`base/` describes the measured Surface Laptop 13 board. The DTS is the source
file; DTBs and DTBOs are build outputs and are ignored by Git.

Overlays are applied by `build.sh dtb` in this order:

1. touchscreen baseline;
2. Bluetooth, for the Bluetooth variant;
3. fingerprint USB, for the fingerprint variant.

The overlays under `experimental/` are never part of the default chain. Add
hardware evidence and a dedicated test target before promoting one.

Use `REBUILD_BASE_DTB=1 ./build.sh dtb` to compile the base DTS. A measured
external DTB can be supplied with `BASE_DTB_INPUT` for comparison, but a clean
checkout must not depend on an ignored or private binary.
