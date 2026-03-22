# Breadcrumb Backend

This service provides the hosted refinement path for Breadcrumb's hybrid architecture.

Current endpoint:

- `GET /healthz`
- `GET /readyz`
- `POST /v1/frame/analyze`

The iOS app remains useful without this service. When the backend is configured, it can improve:

- open-vocabulary label hints
- candidate confidence
- embedding-backed re-identification metadata
- scene summary notes for the local memory graph

## What It Uses

- Grounding DINO model id via `transformers` for open-vocabulary detection
- DINOv2 model id via `transformers` for embeddings
- Optional SAM 2 integration if the official `sam2` package is installed from Meta's repo

The app configures this service with the `BREADCRUMB_BACKEND_URL` environment variable.

## Quick Start

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Set the app-side backend URL:

```bash
export BREADCRUMB_BACKEND_URL=http://127.0.0.1:8000
```

## Verification

Run the backend test suite:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m unittest discover -s tests -v
```

The readiness endpoint distinguishes a live API process from a deployable ML runtime:

- `GET /healthz` reports process liveness
- `GET /readyz` returns `200` only when the required model-serving dependencies are installed
- `POST /v1/frame/analyze` returns `503` with a concrete error if heavy model dependencies are missing

## Optional Environment Variables

- `BREADCRUMB_DEVICE`
- `BREADCRUMB_GROUNDING_DINO_MODEL_ID`
- `BREADCRUMB_DINOV2_MODEL_ID`
- `BREADCRUMB_OPEN_VOCAB_PROMPT`
- `BREADCRUMB_BOX_THRESHOLD`
- `BREADCRUMB_TEXT_THRESHOLD`
- `BREADCRUMB_SAM2_ENABLED`

## Notes

- The service is intentionally real but dependency-heavy. If model dependencies are missing, the endpoint returns a server error with a concrete message rather than silently pretending to analyze frames.
- Session-scale tracking refinement can be layered on top of this endpoint later; the current repo path focuses on live frame refinement because that is what the rebuilt iOS client uses today.
- Deployment guidance and cloud-vs-hybrid tradeoffs are documented in [DEPLOYMENT_STRATEGY.md](./DEPLOYMENT_STRATEGY.md).
