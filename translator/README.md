# Archiver Translator Sidecar

A small local HTTP server running [IndicTrans2](https://github.com/ai4bharat/IndicTrans2)
(AI4Bharat, MIT license) — the SOTA open-source model for Sanskrit and other
Indic languages → English. The Archiver macOS app spawns this process and talks
to it over `localhost`.

## Setup

```bash
cd translator
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### HuggingFace access (required)

Both ai4bharat model repos are **gated** — they now require a HuggingFace account
with access granted per-repository, so the download 401/403s without it:

1. Create/ log in to a [HuggingFace account](https://huggingface.co/join)
2. Visit the repo of the model you plan to use and accept the terms:
   - [`ai4bharat/indictrans2-indic-en-dist-200M`](https://huggingface.co/ai4bharat/indictrans2-indic-en-dist-200M) (default)
   - [`ai4bharat/indictrans2-indic-en-1B`](https://huggingface.co/ai4bharat/indictrans2-indic-en-1B) (larger)
3. Create a read token (Settings → Access Tokens) and log in for the sidecar:

   ```bash
   ./.venv/bin/huggingface-cli login
   ```

The 200M and 1B are approved independently — access to one does not imply the
other. Until access is granted to the 200M, set Settings → Translator → Model to
the 1B (or pass `--model`) — the sidecar will report the auth failure in its
stderr tail on the Settings screen.

The model downloads from HuggingFace on first run (~900 MB for the 200M,
~4 GB for the 1B).

## Run standalone (for debugging)

```bash
python3 server.py --port 8765
# or a different model (e.g. the 1B, if you want to trade speed for size):
python3 server.py --port 8765 --model ai4bharat/indictrans2-indic-en-1B
```

Check it:

```bash
curl localhost:8765/health
curl -X POST localhost:8765/translate \
  -H 'Content-Type: application/json' \
  -d '{"segments":["namaste","iti rāma"],"src_lang":"san_Deva"}'
```

## API

- `GET /health` → `{"status":"ok","model":"<name>"}` (`"loading"` until the model is ready)
- `POST /translate` body `{"segments":[...],"src_lang":"san_Deva"}` → `{"translations":[...]}`
- `GET /` → service card, handy if a browser lands on the port

`src_lang` follows the FLORES code convention (e.g. `san_Deva` for Sanskrit in
Devanagari, `hin_Deva` for Hindi). Output is always English (`eng_Latn`) since
this runs the Indic→English model.

The app launches this server itself (Settings → Translator → Start), passing
`--port` and `--model` from the same fields, and stops it when it quits. Running
it standalone is only needed for debugging.

## OCR fallback (optional)

The app prefers archive.org's existing OCR text layer. When an item has none,
it falls back to local OCR via the `tesseract` CLI:

```bash
brew install tesseract tesseract-lang
```

`tesseract-lang` ships the `san` (Sanskrit) and `deva` (Devanagari) traineddata
the app uses by default.

## Notes

- On Apple Silicon the model runs on the MPS backend automatically; otherwise CPU.
- The default is the 200M distill: ~900 MB to download, roughly 4× smaller and
  faster to load and generate than the 1B. Switch models any time in the app's
  Settings → Translator → Model, or pass `--model` on the command line.