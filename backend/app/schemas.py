from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field


class RectData(BaseModel):
    x: float
    y: float
    width: float
    height: float


class CandidateHint(BaseModel):
    candidate_id: UUID = Field(alias="candidateID")
    bounding_box: RectData = Field(alias="boundingBox")
    confidence: float
    current_event_type: Optional[str] = Field(default=None, alias="currentEventType")

    model_config = {"populate_by_name": True}


class FrameAnalyzeRequest(BaseModel):
    session_id: UUID = Field(alias="sessionID")
    timestamp: datetime
    candidate_hints: list[CandidateHint] = Field(default_factory=list, alias="candidateHints")

    model_config = {"populate_by_name": True}


class RemoteDetection(BaseModel):
    backend_track_id: Optional[str] = Field(default=None, alias="backendTrackID")
    phrase: Optional[str] = None
    confidence: float
    bounding_box: RectData = Field(alias="boundingBox")
    embedding_digest: Optional[str] = Field(default=None, alias="embeddingDigest")
    scene_summary: Optional[str] = Field(default=None, alias="sceneSummary")

    model_config = {"populate_by_name": True}


class FrameAnalyzeResponse(BaseModel):
    detections: list[RemoteDetection]
    scene_summary: Optional[str] = Field(default=None, alias="sceneSummary")
    backend: str

    model_config = {"populate_by_name": True}
