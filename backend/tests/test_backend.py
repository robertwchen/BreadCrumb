import json
import unittest
from io import BytesIO
from unittest.mock import patch
from uuid import UUID

from fastapi import HTTPException, UploadFile
from PIL import Image
from pydantic import ValidationError

from backend.app import main
from backend.app.config import Settings
from backend.app.pipeline import (
    BreadcrumbPerceptionPipeline,
    DetectionRecord,
    PipelineUnavailableError,
    iou,
)
from backend.app.schemas import FrameAnalyzeRequest, FrameAnalyzeResponse, RectData


def make_upload_file() -> UploadFile:
    payload = BytesIO()
    Image.new("RGB", (32, 32), color=(120, 90, 60)).save(payload, format="JPEG")
    payload.seek(0)
    return UploadFile(file=payload, filename="frame.jpg")


class SchemaContractTests(unittest.TestCase):
    def test_frame_request_accepts_ios_aliases(self) -> None:
        request = FrameAnalyzeRequest.model_validate_json(
            json.dumps(
                {
                    "sessionID": "00000000-0000-0000-0000-000000000001",
                    "timestamp": "2026-03-22T05:00:00Z",
                    "candidateHints": [
                        {
                            "candidateID": "00000000-0000-0000-0000-000000000002",
                            "boundingBox": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
                            "confidence": 0.9,
                            "currentEventType": "seen",
                        }
                    ],
                }
            )
        )

        self.assertEqual(request.session_id, UUID("00000000-0000-0000-0000-000000000001"))
        self.assertEqual(len(request.candidate_hints), 1)
        self.assertEqual(request.candidate_hints[0].candidate_id, UUID("00000000-0000-0000-0000-000000000002"))
        self.assertEqual(request.candidate_hints[0].current_event_type, "seen")

    def test_frame_request_rejects_legacy_captured_at_key(self) -> None:
        with self.assertRaises(ValidationError):
            FrameAnalyzeRequest.model_validate_json(
                json.dumps(
                    {
                        "sessionID": "00000000-0000-0000-0000-000000000001",
                        "captured_at": "2026-03-22T05:00:00Z",
                        "candidateHints": [],
                    }
                )
            )


class PipelineLogicTests(unittest.TestCase):
    def test_iou_returns_expected_overlap(self) -> None:
        lhs = RectData(x=0.1, y=0.1, width=0.4, height=0.4)
        rhs = RectData(x=0.3, y=0.3, width=0.4, height=0.4)

        overlap = iou(lhs, rhs)

        self.assertAlmostEqual(overlap, 0.14285714285714288)

    def test_candidate_matching_uses_best_overlap(self) -> None:
        pipeline = BreadcrumbPerceptionPipeline(Settings())
        detection = DetectionRecord(
            phrase="keys",
            confidence=0.82,
            bounding_box=RectData(x=0.1, y=0.1, width=0.25, height=0.25),
            embedding_digest="abc123",
            scene_summary=None,
        )
        hints = FrameAnalyzeRequest.model_validate(
            {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "timestamp": "2026-03-22T05:00:00Z",
                "candidateHints": [
                    {
                        "candidateID": "00000000-0000-0000-0000-000000000010",
                        "boundingBox": {"x": 0.1, "y": 0.1, "width": 0.24, "height": 0.24},
                        "confidence": 0.7,
                        "currentEventType": "seen",
                    },
                    {
                        "candidateID": "00000000-0000-0000-0000-000000000011",
                        "boundingBox": {"x": 0.6, "y": 0.6, "width": 0.2, "height": 0.2},
                        "confidence": 0.7,
                        "currentEventType": "seen",
                    },
                ],
            }
        ).candidate_hints

        matched = pipeline._match_to_candidate_hints([detection], hints)

        self.assertEqual(len(matched), 1)
        self.assertEqual(matched[0].backend_track_id, "00000000-0000-0000-0000-000000000010")
        self.assertEqual(matched[0].phrase, "keys")

    def test_dependency_report_requires_sam2_when_enabled(self) -> None:
        pipeline = BreadcrumbPerceptionPipeline(Settings(sam2_enabled=True))

        def fake_find_spec(module_name: str):
            available = {
                "torch": object(),
                "transformers": object(),
                "sam2": None,
            }
            return available[module_name]

        with patch("backend.app.pipeline.importlib.util.find_spec", side_effect=fake_find_spec):
            report = pipeline.dependency_report()

        self.assertFalse(report["ready"])
        self.assertEqual(report["dependencies"]["torch"], True)
        self.assertEqual(report["dependencies"]["transformers"], True)
        self.assertEqual(report["dependencies"]["sam2"], False)


class EndpointBehaviorTests(unittest.IsolatedAsyncioTestCase):
    async def test_healthz_reports_backend_name(self) -> None:
        payload = await main.healthz()
        self.assertEqual(payload["status"], "ok")
        self.assertIn("backend", payload)

    async def test_readyz_returns_503_for_degraded_runtime(self) -> None:
        with patch.object(
            main.pipeline,
            "dependency_report",
            return_value={
                "ready": False,
                "device": "cpu",
                "sam2Enabled": False,
                "dependencies": {"torch": False, "transformers": False, "sam2": False},
            },
        ):
            response = await main.readyz()

        self.assertEqual(response.status_code, 503)
        payload = json.loads(response.body)
        self.assertEqual(payload["status"], "degraded")
        self.assertEqual(payload["dependencies"]["torch"], False)

    async def test_analyze_frame_rejects_bad_metadata(self) -> None:
        with self.assertRaises(HTTPException) as context:
            await main.analyze_frame(
                metadata='{"sessionID":"00000000-0000-0000-0000-000000000001"}',
                image=make_upload_file(),
            )

        self.assertEqual(context.exception.status_code, 400)

    async def test_analyze_frame_translates_pipeline_unavailable_to_503(self) -> None:
        class UnavailablePipeline:
            def analyze_frame(self, image, request):
                raise PipelineUnavailableError("missing runtime")

        original_pipeline = main.pipeline
        main.pipeline = UnavailablePipeline()
        try:
            with self.assertRaises(HTTPException) as context:
                await main.analyze_frame(
                    metadata=json.dumps(
                        {
                            "sessionID": "00000000-0000-0000-0000-000000000001",
                            "timestamp": "2026-03-22T05:00:00Z",
                            "candidateHints": [],
                        }
                    ),
                    image=make_upload_file(),
                )
        finally:
            main.pipeline = original_pipeline

        self.assertEqual(context.exception.status_code, 503)
        self.assertEqual(context.exception.detail, "missing runtime")

    async def test_analyze_frame_returns_stubbed_response(self) -> None:
        class SuccessPipeline:
            def analyze_frame(self, image, request):
                self.last_request = request
                return FrameAnalyzeResponse(detections=[], sceneSummary="clear desk", backend="stub")

        stub = SuccessPipeline()
        original_pipeline = main.pipeline
        main.pipeline = stub
        try:
            response = await main.analyze_frame(
                metadata=json.dumps(
                    {
                        "sessionID": "00000000-0000-0000-0000-000000000001",
                        "timestamp": "2026-03-22T05:00:00Z",
                        "candidateHints": [],
                    }
                ),
                image=make_upload_file(),
            )
        finally:
            main.pipeline = original_pipeline

        self.assertEqual(response.backend, "stub")
        self.assertEqual(response.scene_summary, "clear desk")
        self.assertEqual(stub.last_request.session_id, UUID("00000000-0000-0000-0000-000000000001"))


if __name__ == "__main__":
    unittest.main()
