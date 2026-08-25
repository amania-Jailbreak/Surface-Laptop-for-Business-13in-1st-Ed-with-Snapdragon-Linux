# Security notes

The build scripts never write to block devices or install to an ESP. Review
all input paths before using generated files in a boot manager.

Do not commit passwords, recovery keys, private firmware dumps, ACPI dumps, or
machine-specific root UUIDs. Report security issues privately to the project
maintainers before public disclosure.
