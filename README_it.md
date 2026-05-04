# flatPDF

<p align="center">
  <img src="docs/flatPDF-icon.png" alt="Icona applicazione flatPDF" width="128">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_it.md">Italiano</a>
</p>

![Release](https://img.shields.io/github/v/release/robertobissanti/flatPDF?label=release&color=blue&cacheSeconds=60)
![Licenza](https://img.shields.io/github/license/robertobissanti/flatPDF?color=blue&cacheSeconds=60)
![Piattaforma](https://img.shields.io/badge/platform-macOS-lightgrey)
![Architettura](https://img.shields.io/badge/arch-Apple%20Silicon-blue)
![Qt](https://img.shields.io/badge/Qt-6.x-41CD52)

flatPDF rende piatti i documenti PDF convertendo ogni pagina in un'immagine temporanea e ricostruendo un nuovo PDF basato su immagini. E' utile quando serve un PDF non modificabile e visivamente stabile, mantenendo l'aspetto originale delle pagine.

## Funzionalita

- Conversione da PDF a PDF piatto
- Rendering intermedio PNG e JPG
- Modalita guidate: Senza Perdite, Massima, Standard, Bassa
- Controllo manuale di DPI e qualita JPG
- Stima rapida della dimensione finale
- Modalita GUI e CLI
- Bundle macOS Apple Silicon con Poppler `pdftoppm` incluso

## Modalita

| Modalita | Formato | DPI | Qualita |
| --- | --- | ---: | ---: |
| Senza Perdite | PNG | 300 | 100 |
| Massima | JPG | 300 | 95 |
| Standard | JPG | 150 | 85 |
| Bassa | JPG | 100 | 60 |

## Compilazione macOS

Build release raccomandata:

```bash
bash scripts/build_release_macos.sh --clean
```

Lo script pulisce gli artefatti locali ignorati, compila l'app Apple Silicon, inserisce Qt e Poppler nel bundle, firma l'app ad-hoc, esegue i test CLI e crea `dist/flatPDF-v0.1-macos-arm64.zip`.

Build manuale:

```bash
cmake --preset macos-arm64
cmake --build --preset macos-arm64
```

Sono disponibili anche i preset Intel e universal:

```bash
cmake --preset macos-x86_64
cmake --build --preset macos-x86_64
```

```bash
cmake --preset macos-universal
cmake --build --preset macos-universal
```

L'applicazione generata e' `flatPDF.app` nella cartella di build selezionata.

## Bundle Poppler

Dopo la compilazione e `macdeployqt`, inserisci `pdftoppm` e le librerie necessarie nel bundle:

```bash
/Applications/Qt/6.9.1/macos/bin/macdeployqt build-macos-arm64/flatPDF.app
bash scripts/bundle_pdftoppm.sh build-macos-arm64/flatPDF.app /opt/homebrew/bin/pdftoppm
```

## CLI

```bash
./build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF --cli --input input.pdf --output output.pdf --preset standard
```

Stima rapida:

```bash
./build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF --cli --input input.pdf --estimate --preset standard
```

La stima rapida campiona il 20% del documento, fino a un massimo di 10 pagine, e proietta da quelle pagine la dimensione finale del file.

## Test

```bash
bash scripts/test_cli.sh build-macos-arm64/flatPDF.app/Contents/MacOS/flatPDF
```

## Licenza

GPL v2.

Copyright (c) 2025-2026 Roberto Bissanti  
roberto.bissanti@gmail.com
