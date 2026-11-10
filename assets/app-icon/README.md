# Lightcept app icon

The icon uses a dark rounded-square body, standard macOS optical padding, and an `L` formed from a
photo crop-frame corner with a violet exposure wedge.

`lightcept-1024.png` is the production master. `lightcept-dock-512.png` is the
README preview, and `lightcept.icns` is the macOS bundle icon. The transparent
surround is preserved so the Dock icon aligns with standard macOS icons.

`ui/neiv/app.json` references `lightcept.icns` through the
`ui/neiv/lightcept.icns` symlink. Neiv copies it to
`Contents/Resources/icon.icns` and sets `CFBundleIconFile` to `icon.icns`.

The `concepts/` directory retains the explored Lightcept variants. The icon is
original work for this repository and is covered by the repository's Mozilla
Public License 2.0 terms; see `../../LICENSE`. No separate icon license file is
needed because the root license already grants rights to the complete work.
