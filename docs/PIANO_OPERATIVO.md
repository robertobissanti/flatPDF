# Piano operativo

## Obiettivi

- Rendere scriptabile il convertitore con una modalita CLI.
- Consentire la rasterizzazione intermedia sia in PNG sia in JPG.
- Rendere effettive le opzioni DPI e qualita.
- Aggiungere preset guidati: Senza Perdite, Massima, Standard, Bassa.
- Aggiungere una stima della dimensione finale solo quando richiesta.
- Coprire le funzionalita principali con test bash ripetibili.

## Linee guida

- La GUI deve restare il comportamento predefinito quando l'app viene aperta senza argomenti.
- La CLI deve evitare effetti collaterali da GUI, inclusa l'apertura automatica della cartella di output.
- I preset sono scorciatoie, non vincoli: la CLI puo sovrascrivere DPI, qualita e formato.
- La modalita "Senza Perdite" usa PNG e qualita 100; le modalita compresse usano JPG e passano la qualita a `pdftoppm`.
- La stima deve essere esplicita: si genera un PDF temporaneo con le stesse impostazioni e si restituisce la dimensione stimata senza salvare nel percorso finale.
- I test non devono dipendere da file utente: creano un PDF sintetico temporaneo e verificano output non vuoti, preset, stima, differenze DPI e differenze qualita.

## Preset

| Preset | DPI | Qualita | Formato |
| --- | ---: | ---: | --- |
| Senza Perdite | 300 | 100 | PNG |
| Massima | 300 | 95 | JPG |
| Standard | 150 | 85 | JPG |
| Bassa | 100 | 60 | JPG |

## Verifiche attese

- `--list-presets` elenca tutti i preset.
- `--cli --preset standard` produce un PDF valido.
- `--cli --format png` produce un PDF valido usando immagini intermedie PNG.
- `--cli --estimate` restituisce `estimatedBytes` e non richiede `--output`.
- A DPI maggiore, a parita di qualita e formato, il PDF finale aumenta sensibilmente.
- A qualita JPG maggiore, a parita di DPI, il PDF finale cambia dimensione rispetto alla qualita bassa.
