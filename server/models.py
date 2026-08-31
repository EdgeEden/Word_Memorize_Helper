from pydantic import BaseModel, Field
from typing import Dict, Any, Optional

class LoginRequest(BaseModel):
    username: str = Field(..., min_length=1, max_length=50, description="Unique username")

class LoginResponse(BaseModel):
    id: int
    username: str
    is_new: bool
    cards: Dict[str, Any]

class SyncRequest(BaseModel):
    username: str
    cards: Dict[str, Any]

class SyncResponse(BaseModel):
    status: str
    saved_count: int
    updated_at: str

class HealthResponse(BaseModel):
    status: str
    version: str

class AppVersionResponse(BaseModel):
    version: str
    version_code: int
    min_supported_version_code: int = 1
    title: str
    release_notes: str
    apk_url: str
    windows_url: str
    force_update: bool = False
    pub_date: str


