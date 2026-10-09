#!/usr/bin/env python3
"""IndicTrans2 translation sidecar for Archiver.

Loads an IndicTrans2 (Indic -> English) model once at startup and serves a
tiny HTTP API used by the Swift app:

    GET  /health    -> {"status": "ok", "model": <name>}
    POST /translate -> {"segments": [...], "src_lang": "san_Deva"}
                   -> {"translations": [...]}

Run standalone for debugging:

    python3 server.py --port 8765
    curl localhost:8765/health
    curl -X POST localhost:8765/translate \
         -H 'Content-Type: application/json' \
         -d '{"segments":["namaste","iti rāma"], "src_lang":"san_Deva"}'
"""

from __future__ import annotations

import argparse
import logging
import os
from contextlib import asynccontextmanager
from typing import List

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
from IndicTransToolkit import IndicProcessor

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("translator")

DEFAULT_MODEL = os.environ.get(
    "TRANSLATOR_MODEL", "ai4bharat/indictrans2-indic-en-dist-200M"
)
TARGET_LANG = "eng_Latn"  # IndicTrans2 indic-en always emits English (Latin)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # The model is loaded exactly once, here. `main()` records any --model
    # override in `state` before uvicorn starts, so the Swift app's Settings
    # choice is authoritative — previously the override loaded a model and the
    # startup hook then overwrote it with the import-time default.
    state.update(load_model(state["model_name"]))
    yield
    state.clear()


app = FastAPI(title="Archiver Translator", lifespan=lifespan)

state: dict = {"model_name": DEFAULT_MODEL}


class TranslateRequest(BaseModel):
    segments: List[str]
    src_lang: str = "san_Deva"


class TranslateResponse(BaseModel):
    translations: List[str]


def load_model(model_name: str):
    log.info("Loading model %s ...", model_name)
    device = "cuda" if torch.cuda.is_available() else (
        "mps" if torch.backends.mps.is_available() else "cpu"
    )
    tokenizer = AutoTokenizer.from_pretrained(model_name, trust_remote_code=True)
    model = AutoModelForSeq2SeqLM.from_pretrained(
        model_name, trust_remote_code=True
    ).to(device)
    model.eval()
    processor = IndicProcessor(inference=True)
    log.info("Model loaded on %s", device)
    return {
        "tokenizer": tokenizer,
        "model": model,
        "processor": processor,
        "device": device,
        "name": model_name,
    }


@app.get("/health")
def health():
    ready = state.get("model") is not None
    return {"status": "ok" if ready else "loading", "model": state.get("name", "")}


@app.get("/")
def index():
    # Handy when a browser or curiosity points at the port.
    return {
        "service": "Archiver Translator",
        "model": state.get("name", ""),
        "endpoints": {
            "health": "GET /health",
            "translate": "POST /translate",
        },
    }


@app.post("/translate", response_model=TranslateResponse)
def translate(req: TranslateRequest):
    model = state.get("model")
    if model is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    if not req.segments:
        return TranslateResponse(translations=[])

    tokenizer = state["tokenizer"]
    processor = state["processor"]
    device = state["device"]

    # The client relies on a 1:1 mapping (one translation per input segment) to
    # rebuild the bilingual document, so we do NOT split segments here. The
    # tokenizer truncates over-long inputs (truncation=True, max_length=256).
    segments = req.segments

    # Preprocess + batched generation. Batch size kept modest for memory.
    BATCH = 16
    results: List[str] = []
    for i in range(0, len(segments), BATCH):
        chunk = segments[i : i + BATCH]
        batch = processor.preprocess_batch(
            chunk, src_lang=req.src_lang, tgt_lang=TARGET_LANG
        )
        inputs = tokenizer(
            batch,
            truncation=True,
            padding="longest",
            max_length=256,
            return_tensors="pt",
        ).to(device)
        with torch.no_grad():
            generated = model.generate(
                **inputs,
                max_length=256,
                num_beams=4,
                do_sample=False,
            )
        decoded = tokenizer.batch_decode(
            generated, skip_special_tokens=True, clean_up_tokenization_spaces=True
        )
        decoded = processor.postprocess_batch(decoded, lang=TARGET_LANG)
        results.extend(decoded)

    return TranslateResponse(translations=results)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    args = parser.parse_args()

    # Record the requested model before the lifespan handler runs. Setting only
    # the env var is not enough: DEFAULT_MODEL above was already bound at import.
    state["model_name"] = args.model
    os.environ["TRANSLATOR_MODEL"] = args.model

    import uvicorn

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()