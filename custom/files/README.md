# custom/files

System files overlaid onto the image root.

The tree under `custom/files/` mirrors the image filesystem, so
`custom/files/usr/lib/systemd/system/foo.service` lands at
`/usr/lib/systemd/system/foo.service`. Use it for systemd units, presets,
tmpfiles.d and sysusers.d entries, and other system payloads the template ships.

`custom/config/` is the seam for new-user configuration instead. The `customize`
skill decides which seam a given file belongs in.
