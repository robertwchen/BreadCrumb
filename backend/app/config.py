from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="BREADCRUMB_", env_file=".env", extra="ignore")

    device: str = "cpu"
    grounding_dino_model_id: str = "IDEA-Research/grounding-dino-base"
    dinov2_model_id: str = "facebook/dinov2-base"
    open_vocab_prompt: str = (
        "keys . wallet . phone . glasses . bottle . cup . remote . medicine bottle . bag . "
        "notebook . headphones . watch . charger . case . pouch . toy . tool . container ."
    )
    box_threshold: float = 0.32
    text_threshold: float = 0.24
    sam2_enabled: bool = False
    max_detections: int = 16
    backend_name: str = "grounding-dino+dinov2"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
