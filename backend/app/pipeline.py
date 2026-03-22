import hashlib
import importlib
import importlib.util
from dataclasses import dataclass
from typing import Optional

import numpy as np
from PIL import Image

from .config import Settings
from .schemas import CandidateHint, FrameAnalyzeRequest, FrameAnalyzeResponse, RectData, RemoteDetection


class PipelineUnavailableError(RuntimeError):
    pass


@dataclass
class DetectionRecord:
    phrase: str | None
    confidence: float
    bounding_box: RectData
    embedding_digest: str | None
    scene_summary: str | None


class BreadcrumbPerceptionPipeline:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._torch = None
        self._grounding_processor = None
        self._grounding_model = None
        self._embedding_processor = None
        self._embedding_model = None
        self._sam2_predictor = None

    def dependency_report(self) -> dict[str, object]:
        torch_available = importlib.util.find_spec("torch") is not None
        transformers_available = importlib.util.find_spec("transformers") is not None
        sam2_available = importlib.util.find_spec("sam2") is not None if self.settings.sam2_enabled else False

        ready = torch_available and transformers_available and (
            not self.settings.sam2_enabled or sam2_available
        )

        return {
            "ready": ready,
            "device": self.settings.device,
            "sam2Enabled": self.settings.sam2_enabled,
            "dependencies": {
                "torch": torch_available,
                "transformers": transformers_available,
                "sam2": sam2_available,
            },
        }

    def analyze_frame(self, image: Image.Image, request: FrameAnalyzeRequest) -> FrameAnalyzeResponse:
        detections = self._detect(image)
        enriched = [self._enrich_with_embedding(image, detection) for detection in detections]
        matched = self._match_to_candidate_hints(enriched, request.candidate_hints)

        scene_summary = None
        if matched:
            phrases = [d.phrase for d in matched if d.phrase]
            if phrases:
                scene_summary = "Detected: " + ", ".join(phrases[:4])

        return FrameAnalyzeResponse(
            detections=matched,
            sceneSummary=scene_summary,
            backend=self.settings.backend_name,
        )

    def _detect(self, image: Image.Image) -> list[DetectionRecord]:
        processor, model, torch = self._load_grounding_dino()

        inputs = processor(
            images=image,
            text=self.settings.open_vocab_prompt,
            return_tensors="pt",
        )
        inputs = {key: value.to(self.settings.device) for key, value in inputs.items()}

        with torch.no_grad():
            outputs = model(**inputs)

        results = processor.post_process_grounded_object_detection(
            outputs,
            inputs["input_ids"],
            box_threshold=self.settings.box_threshold,
            text_threshold=self.settings.text_threshold,
            target_sizes=[(image.height, image.width)],
        )

        detections: list[DetectionRecord] = []
        for result in results:
            boxes = result.get("boxes", [])
            scores = result.get("scores", [])
            labels = result.get("labels", [])

            for box, score, label in zip(boxes[: self.settings.max_detections], scores, labels):
                left, top, right, bottom = [float(value) for value in box.tolist()]
                width = max(0.0, right - left)
                height = max(0.0, bottom - top)
                if width <= 0 or height <= 0:
                    continue

                detections.append(
                    DetectionRecord(
                        phrase=str(label),
                        confidence=float(score),
                        bounding_box=RectData(x=left / image.width, y=top / image.height, width=width / image.width, height=height / image.height),
                        embedding_digest=None,
                        scene_summary=None,
                    )
                )

        return detections

    def _enrich_with_embedding(self, image: Image.Image, detection: DetectionRecord) -> DetectionRecord:
        processor, model, torch = self._load_dinov2()
        crop = self._crop(image, detection.bounding_box)
        inputs = processor(images=crop, return_tensors="pt")
        pixel_values = inputs["pixel_values"].to(self.settings.device)

        with torch.no_grad():
            outputs = model(pixel_values=pixel_values)

        embedding = outputs.last_hidden_state[:, 0, :].detach().cpu().numpy().flatten()
        digest = hashlib.sha256(embedding.astype(np.float32).tobytes()).hexdigest()[:24]

        return DetectionRecord(
            phrase=detection.phrase,
            confidence=detection.confidence,
            bounding_box=detection.bounding_box,
            embedding_digest=digest,
            scene_summary=detection.scene_summary,
        )

    def _match_to_candidate_hints(
        self,
        detections: list[DetectionRecord],
        candidate_hints: list[CandidateHint],
    ) -> list[RemoteDetection]:
        response: list[RemoteDetection] = []

        for detection in detections:
            backend_track_id: Optional[str] = None
            best_iou = 0.0
            for hint in candidate_hints:
                overlap = iou(detection.bounding_box, hint.bounding_box)
                if overlap > best_iou and overlap > 0.35:
                    backend_track_id = str(hint.candidate_id)
                    best_iou = overlap

            response.append(
                RemoteDetection(
                    backendTrackID=backend_track_id,
                    phrase=detection.phrase,
                    confidence=detection.confidence,
                    boundingBox=detection.bounding_box,
                    embeddingDigest=detection.embedding_digest,
                    sceneSummary=detection.scene_summary,
                )
            )

        return response

    def _crop(self, image: Image.Image, rect: RectData) -> Image.Image:
        left = int(max(0, rect.x * image.width))
        top = int(max(0, rect.y * image.height))
        right = int(min(image.width, (rect.x + rect.width) * image.width))
        bottom = int(min(image.height, (rect.y + rect.height) * image.height))
        return image.crop((left, top, right, bottom))

    def _load_grounding_dino(self):
        if self._grounding_processor is not None and self._grounding_model is not None and self._torch is not None:
            return self._grounding_processor, self._grounding_model, self._torch

        try:
            torch = importlib.import_module("torch")
            transformers = importlib.import_module("transformers")
        except ImportError as error:
            raise PipelineUnavailableError(
                "Grounding DINO dependencies are unavailable. Install backend requirements first."
            ) from error

        processor_cls = getattr(transformers, "AutoProcessor", None)
        model_cls = getattr(transformers, "AutoModelForZeroShotObjectDetection", None)
        if processor_cls is None or model_cls is None:
            raise PipelineUnavailableError(
                "Installed transformers build does not expose Grounding DINO zero-shot detection APIs."
            )

        self._grounding_processor = processor_cls.from_pretrained(self.settings.grounding_dino_model_id)
        self._grounding_model = model_cls.from_pretrained(self.settings.grounding_dino_model_id).to(self.settings.device)
        self._grounding_model.eval()
        self._torch = torch
        return self._grounding_processor, self._grounding_model, torch

    def _load_dinov2(self):
        if self._embedding_processor is not None and self._embedding_model is not None and self._torch is not None:
            return self._embedding_processor, self._embedding_model, self._torch

        try:
            torch = importlib.import_module("torch")
            transformers = importlib.import_module("transformers")
        except ImportError as error:
            raise PipelineUnavailableError(
                "DINOv2 dependencies are unavailable. Install backend requirements first."
            ) from error

        processor_cls = getattr(transformers, "AutoImageProcessor", None)
        model_cls = getattr(transformers, "AutoModel", None)
        if processor_cls is None or model_cls is None:
            raise PipelineUnavailableError(
                "Installed transformers build does not expose DINOv2 embedding APIs."
            )

        self._embedding_processor = processor_cls.from_pretrained(self.settings.dinov2_model_id)
        self._embedding_model = model_cls.from_pretrained(self.settings.dinov2_model_id).to(self.settings.device)
        self._embedding_model.eval()
        self._torch = torch
        return self._embedding_processor, self._embedding_model, torch


def iou(lhs: RectData, rhs: RectData) -> float:
    left = max(lhs.x, rhs.x)
    top = max(lhs.y, rhs.y)
    right = min(lhs.x + lhs.width, rhs.x + rhs.width)
    bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)

    if right <= left or bottom <= top:
        return 0.0

    intersection = (right - left) * (bottom - top)
    lhs_area = lhs.width * lhs.height
    rhs_area = rhs.width * rhs.height
    union = lhs_area + rhs_area - intersection
    return float(intersection / union) if union > 0 else 0.0
