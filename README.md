# flatPDF

<p align="center">
  <img src="docs/flatPDF-icon.png" alt="flatPDF app icon" width="128">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_it.md">Italiano</a>
</p>

![Release](https://img.shields.io/github/v/release/robertobissanti/flatPDF?label=release&color=blue&cacheSeconds=60)
![License](https://img.shields.io/github/license/robertobissanti/flatPDF?color=blue&cacheSeconds=60)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Architecture](https://img.shields.io/badge/arch-Apple%20Silicon-blue)
![Qt](https://img.shields.io/badge/Qt-6.x-41CD52)

flatPDF flattens PDF documents by rendering each page to a temporary image and rebuilding a new image-based PDF. This is useful when you need a non-editable, visually stable PDF while preserving the original page appearance.

## Features

- PDF to flat PDF conversion
- PNG and JPG intermediate rendering
- Guided presets: Lossless, Maximum, Standard, Low
- Manual DPI and JPG quality controls
- Quick final-size estimate based on sample pages
- GUI and CLI modes
- macOS Apple Silicon bundle with bundled Poppler `pdftoppm`

## Presets

| Preset | Format | DPI | Quality |
| --- | --- | ---: | ---: |
| Lossless | PNG | 300 | 100 |
| Maximum | JPG | 300 | 95 |
| Standard | JPG | 150 | 85 |
| Low | JPG | 100 | 60 |

## Build on macOS

Recommended release build:

```bash
bash scripts/build_release_macos.sh --clean
```

The script cleans ignored local artifacts, builds the Apple Silicon app, bundles Qt and Poppler, signs the app ad-hoc, runs CLI tests, and creates `dist/flatPDF-v0.1-macos-arm64.zip`.

Manual build:

```bash
cmake --preset macos-arm64
cmake --build --preset macos-arm64
```

Intel and universal presets are also available:

```bash
cmake --preset macos-x86_64
cmake --build --preset macos-x86_64
```

```bash
cmake --preset macos-universal
cmake --build --preset macos-universal
```

The generated application is `flatPDF.app` in the selected build directory.

## Bundle Poppler

After building and running `macdeployqt`, bundle `pdftoppm` and its required libraries:

```bash
/Applications/Qt/6.9.1/macos/bin/macdeployqt build-macos-arm64/flatPDF.app
bash scripts/bundle_pdftoppm.sh build-macos-arm64/flatPDF.app /opt/homebrew/bin/pdftoppm
```

## CLI

```bash
./build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF --cli --input input.pdf --output output.pdf --preset standard
```

Quick estimate:

```bash
./build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF --cli --input input.pdf --estimate --preset standard
```

The quick estimate samples 20% of the document, up to a maximum of 10 pages, and projects the final file size from those sample pages.

## Test

```bash
bash scripts/test_cli.sh build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF
```

## License

GPL v2.

Copyright (c) 2025-2026 Roberto Bissanti  
roberto.bissanti@gmail.com
