# flatPDF

flatPDF converte un PDF in immagini temporanee e ricrea un PDF piatto.

## Build macOS

Il progetto usa un solo sorgente per Apple Silicon, Intel e build universal.

```bash
cmake --preset macos-arm64
cmake --build --preset macos-arm64
```

```bash
cmake --preset macos-x86_64
cmake --build --preset macos-x86_64
```

```bash
cmake --preset macos-universal
cmake --build --preset macos-universal
```

L'app viene generata come `flatPDF.app` nella cartella di build scelta.

## CLI

```bash
./build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF --cli --input input.pdf --output output.pdf --preset standard
```

Preset disponibili:

- `lossless`: PNG, 300 DPI, qualita 100
- `massima`: JPG, 300 DPI, qualita 95
- `standard`: JPG, 150 DPI, qualita 85
- `bassa`: JPG, 100 DPI, qualita 60

Stima rapida:

```bash
./build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF --cli --input input.pdf --estimate --preset standard
```

La stima rapida campiona al massimo prima pagina, pagina centrale e ultima pagina.
