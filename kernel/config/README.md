# Kernel configuration

`base.config` is the hardware-support starting point for the X1P42100 board.
The build script rewrites only `CONFIG_LOCALVERSION` and disables automatic
SCM suffixes so the release is reproducible and neutral.

The relevant paths are built in or enabled as modules according to the
configuration. Check the resulting `.config` and `modules.dep` after changing
the kernel source.
