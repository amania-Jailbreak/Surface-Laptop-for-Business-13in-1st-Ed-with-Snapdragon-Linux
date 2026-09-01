# Contributing

Keep changes focused on Surface hardware support. Do not add root filesystems,
desktop packages, installer media, secrets, or disk images.

Before submitting a change:

```sh
./build.sh check
./build.sh dtb
./build.sh verify
```

Maintainers may use `./build.sh release` to produce a GitHub Release asset.
Release builds must use a real target command line and separately obtained,
license-compliant firmware. Do not commit the generated package or recovery
set.

For kernel changes, record the source revision, configuration delta, DTB
selection, firmware requirements, and real-hardware result. Unvalidated
experiments belong under an explicit experimental directory and must not be
selected by the default package target.
