# Lightcept Neiv desktop app

Neiv is Lightcept's macOS desktop host. Weiv renders the page, Cyna owns app
commands and document state, and an app-owned native plugin displays completed
RGBA frames in native `NSImageView` surfaces. Image bytes and source paths stay
outside the web page.

The app imports the headless `lightcept_core` package as a local Cyna path
dependency. For qualified compressed Ricoh DNGs, its document service reads a
bounded source, prepares a scene-linear working preview, and invokes the native
engine pipeline. The native provider copies only a completed frame and checks
the active document generation before publication. The same path handles the
inspected Nikon Z8 lossless and Z6 II packed 14-bit NEF layouts.
The NEF route applies the source camera neutral to clipped highlights, so a
fully saturated neutral sky stays white after the as-shot color gains.

## Build

From the repository root:

```sh
scripts/setup-cyna-toolchain.sh
ui/neiv/build.sh
```

The build produces `ui/neiv/build/NeivApp.app`. It bundles the Lightcept
icon, the sRGB profile, and the headless TIFF and preview workers. It does not
build or bundle Rust.

`cyna.toml` sets the app host to the Cyna `debug` profile. The pinned compiler
emits a very large LLVM module for the current app initializer, and release
`-O2` compilation can exceed 40 minutes. The headless engine and bundled worker
tools remain release builds.

## Run

```sh
open ui/neiv/build/NeivApp.app
```

The app opens qualified DNG and NEF sources, publishes a native preview, and
supports the committed develop controls, edit history, project save/reopen, and
TIFF export documented in the app UI.

## Scope

The app currently supports the exact source variants qualified in the
private `neucine/daydream` qualification index at
`projects/lightcept/qualification/README.md`. Other cameras, compression
variants, and DNG layouts fail closed and preserve the current photograph. Full
export parity for every qualified route remains an implementation gate.

Desktop architecture and project replay details live in the
private `neucine/daydream` architecture records under `projects/lightcept/`.
