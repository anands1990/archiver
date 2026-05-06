# Archiver

A minimal, native macOS menu bar app that downloads books from [archive.org](https://archive.org) as PDFs and uploads them to Google Drive — with optional metadata extraction via local LM Studio.

![Screenshot](<img width="1856" height="2304" alt="Gemini_Generated_Image_d1tjsjd1tjsjd1tj" src="https://github.com/user-attachments/assets/9d8a5e7b-95b8-4145-9c2d-ac7de7ab1bc9" />

## Features

- **Native macOS menu bar app** — lives in your menu bar, no dock icon
- **Drag & drop or paste URLs** — supports batch uploads
- **Metadata preview** — review and edit metadata before uploading
- **Google Drive OAuth** — secure OAuth 2.0 PKCE flow with keychain token storage
- **LM Studio integration** — extract book metadata using a local LLM
- **Streaming uploads** — large PDFs are uploaded from disk, not loaded into RAM
- **Atomic downloads** — resumes safely, avoids partial file corruption

## Requirements

- macOS 14+ (Sonoma)
- Swift 5.9+
- [Google Drive API credentials](https://developers.google.com/workspace/guides/create-credentials) (OAuth 2.0 Desktop app)
- Optional: [LM Studio](https://lmstudio.ai/) running locally for metadata extraction

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
4. Paste an archive.org book URL and click **Upload**

## Architecture

Pure Swift — no Python backend. Networking is done via `URLSession`:

- `ArchiveClient.swift` — archive.org metadata + PDF download
- `LMStudioClient.swift` — OpenAI-compatible `/v1/chat/completions` API
- `GoogleDriveClient.swift` — OAuth + Drive multipart upload
- `UploadPipeline.swift` — orchestrates resolve → metadata → download → upload

## License

MIT
