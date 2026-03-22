import io

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image

from .config import get_settings
from .pipeline import BreadcrumbPerceptionPipeline, PipelineUnavailableError
from .schemas import FrameAnalyzeRequest, FrameAnalyzeResponse


settings = get_settings()
pipeline = BreadcrumbPerceptionPipeline(settings)
app = FastAPI(title="Breadcrumb Backend", version="0.1.0")


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok", "backend": settings.backend_name}


@app.get("/readyz")
async def readyz() -> JSONResponse:
    report = pipeline.dependency_report()
    payload = {"status": "ready" if report["ready"] else "degraded", "backend": settings.backend_name, **report}
    status_code = 200 if report["ready"] else 503
    return JSONResponse(status_code=status_code, content=payload)


@app.post("/v1/frame/analyze", response_model=FrameAnalyzeResponse)
async def analyze_frame(
    metadata: str = Form(...),
    image: UploadFile = File(...),
) -> FrameAnalyzeResponse:
    try:
        request = FrameAnalyzeRequest.model_validate_json(metadata)
    except Exception as error:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"Invalid metadata payload: {error}") from error

    try:
        payload = await image.read()
        pil_image = Image.open(io.BytesIO(payload)).convert("RGB")
    except Exception as error:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"Invalid image payload: {error}") from error

    try:
        return pipeline.analyze_frame(pil_image, request)
    except PipelineUnavailableError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except Exception as error:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"Frame analysis failed: {error}") from error
