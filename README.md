# Archiver

A minimal, native macOS menu bar app that downloads books from [archive.org](https://archive.org) as PDFs and uploads them to Google Drive — with optional bilingual Sanskrit → English translation.

<img width="350" height="450" alt="screenshots" src="https://github.com/user-attachments/assets/9d8a5e7b-95b8-4145-9c2d-ac7de7ab1bc9" />

## Features

- **Native macOS menu bar app** — lives in your menu bar, no dock icon
- **Drag & drop or paste URLs** — supports batch uploads
- **Metadata preview** — review and edit metadata before uploading; the Drive filename previews live as you type
- **Google Drive OAuth** — secure OAuth 2.0 PKCE flow with keychain token storage
- **Duplicate detection** — books already in the destination folder are skipped instead of stacking copies on every re-run
- **Streaming uploads** — large PDFs are streamed from disk, never loaded into RAM
- **Atomic downloads** — a failed or cancelled download leaves an `.incomplete` file, never a truncated PDF
- **Bilingual translation (optional)** — archive.org's OCR text layer translated by a local IndicTrans2 sidecar and uploaded as interleaved Sanskrit/English Markdown. Lines the model can't parse are returned untranslated, so they're romanised and marked instead of left as dead English
- **Local OCR fallback (optional)** — when an item has no text layer, pages are rasterised and read with `tesseract`

## Requirements

- macOS 14+ (Sonoma)
- Swift 5.9+
- [Google Drive API credentials](https://developers.google.com/workspace/guides/create-credentials) (OAuth 2.0 Desktop app)
- Optional, for translation: [Python sidecar setup](translator/README.md) — note
this needs a HuggingFace account with access granted to the model repo.
- Optional, for OCR fallback: `brew install tesseract tesseract-lang`

## Build

```bash
cd ArchiveUploaderApp
swift build -c release
./build.sh
```

The built app will be at `dist/Archiver.app`.

## Usage

1. Launch `Archiver.app` from the menu bar
2. Open **Settings** (gear icon) and paste your Google Drive `credentials.json`
3. Click **Auth** to complete OAuth
4. Paste an archive.org book URL and click **Upload** — or **Preview** to review the metadata and filename first

Turn on **Translate to English** to also produce a bilingual document. Start the translator once from Settings → Translator (it keeps running between uploads, and stops itself when the app quits).

## Architecture

Pure Swift for the app itself; the only external process is the local Python translation sidecar.

- `ArchiveClient.swift` — archive.org metadata, streaming PDF download, OCR text layer
- `GoogleDriveClient.swift` — OAuth 2.0 PKCE, Drive multipart upload, duplicate lookup
- `UploadPipeline.swift` — orchestrates resolve → metadata → download → translate → upload
- `TranslatorClient.swift` / `SidecarProcess.swift` — HTTP client for and supervisor of the IndicTrans2 sidecar
- `OCRClient.swift` — PDFKit rasterisation + `tesseract` CLI fallback
- `BilingualDocument.swift` — page/paragraph segmentation and interleaved Markdown rendering
- `Motion.swift` — shared animation vocabulary: press feedback, shimmer, sparkle, reduced-motion gating

## Optional: Sanskrit → English translation

```bash
cd translator
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

The model downloads from HuggingFace on first run (~900 MB for the default
200M distill). The app finds the venv automatically and talks to the sidecar
over `localhost`. See [translator/README.md](translator/README.md) for the API
and CLI flags.

## License

MIT
