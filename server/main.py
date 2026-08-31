import os
import uvicorn
from datetime import datetime
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from fastapi.responses import FileResponse
from database import init_db, login_or_register_user, get_user_cards, upsert_user_cards, delete_user_cards
from models import LoginRequest, LoginResponse, SyncRequest, SyncResponse, HealthResponse, AppVersionResponse

app = FastAPI(
    title="WordN Vocabulary Sync API",
    description="Backend API for WordN FSRS Vocabulary and Wrong Words Synchronization",
    version="1.0.0"
)

DIST_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dist")

# Current published latest version info
LATEST_VERSION_CONFIG = {
    "version": "1.0.3",
    "version_code": 4,
    "min_supported_version_code": 1,
    "title": "WordN v1.0.3 体验升级",
    "release_notes": "1. 🤖 支持自定义 AI 大模型：可动态拉取可用模型列表，且答题反馈中展示具体判定模型\n2. 🚀 体验与更新优化：修复 Android 端应用内 OTA 升级拉起，并增强模型切换与状态校验",
    "apk_url": "/api/download/apk",
    "windows_url": "/api/download/windows",
    "force_update": False,
    "pub_date": "2026-08-30T15:45:00Z"
}




# Enable CORS for Flutter Web & Mobile
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def on_startup():
    init_db()

@app.get("/api/health", response_model=HealthResponse)
def health_check():
    return {
        "status": "healthy",
        "app": "WordN Sync Server",
        "timestamp": datetime.utcnow().isoformat()
    }

@app.post("/api/login", response_model=LoginResponse)
def login_or_register(payload: LoginRequest):
    username = payload.username.strip().lower()
    if not username:
        raise HTTPException(status_code=400, detail="Username cannot be empty")

    dict_id = payload.dict_id.strip().lower() if payload.dict_id else "kaoyan4533"
    user_info = login_or_register_user(username)
    cards = get_user_cards(username, dict_id=dict_id)
    return {
        "id": user_info["id"],
        "username": user_info["username"],
        "is_new": user_info["is_new"],
        "cards": cards
    }

@app.get("/api/cards")
def fetch_cards(
    username: str = Query(..., min_length=1),
    dict_id: str = Query("kaoyan4533")
):
    clean_username = username.strip().lower()
    clean_dict_id = dict_id.strip().lower() if dict_id else "kaoyan4533"
    cards = get_user_cards(clean_username, dict_id=clean_dict_id)
    return {
        "username": clean_username,
        "dict_id": clean_dict_id,
        "cards": cards,
        "count": len(cards),
        "updated_at": datetime.utcnow().isoformat()
    }

@app.post("/api/cards/sync", response_model=SyncResponse)
def sync_cards(payload: SyncRequest):
    clean_username = payload.username.strip().lower()
    if not clean_username:
        raise HTTPException(status_code=400, detail="Username cannot be empty")

    clean_dict_id = payload.dict_id.strip().lower() if payload.dict_id else "kaoyan4533"

    # Ensure user exists
    login_or_register_user(clean_username)
    saved = upsert_user_cards(clean_username, payload.cards, dict_id=clean_dict_id)
    return {
        "status": "ok",
        "saved_count": saved,
        "updated_at": datetime.utcnow().isoformat()
    }

@app.delete("/api/cards")
def clear_cards(
    username: str = Query(..., min_length=1),
    dict_id: str = Query(None, description="Specific dict_id or empty for all dicts")
):
    clean_username = username.strip().lower()
    clean_dict = dict_id.strip().lower() if (dict_id and dict_id.strip().lower() != "all") else None
    deleted = delete_user_cards(clean_username, clean_dict)
    return {
        "status": "ok",
        "username": clean_username,
        "dict_id": clean_dict or "all",
        "deleted_count": deleted,
        "timestamp": datetime.utcnow().isoformat()
    }

@app.get("/api/version/latest", response_model=AppVersionResponse)
def get_latest_version():
    return LATEST_VERSION_CONFIG

@app.get("/api/download/apk")
def download_apk():
    apk_candidates = [
        os.path.join(DIST_DIR, "WordN_Android_Release.apk"),
        os.path.join(DIST_DIR, "app-release.apk"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "WordN_Android_Release.apk"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "app", "outputs", "flutter-apk", "app-release.apk")
    ]
    for p in apk_candidates:
        if os.path.exists(p):
            return FileResponse(p, media_type="application/vnd.android.package-archive", filename="WordN_Android_Release.apk")
    raise HTTPException(status_code=404, detail="Release APK not found on server")

@app.get("/api/download/windows")
def download_windows():
    zip_candidates = [
        os.path.join(DIST_DIR, "WordN_Windows_x64.zip"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "WordN_Windows_x64.zip")
    ]
    for p in zip_candidates:
        if os.path.exists(p):
            return FileResponse(p, media_type="application/zip", filename="WordN_Windows_x64.zip")
    raise HTTPException(status_code=404, detail="Release Windows ZIP not found on server")

if __name__ == "__main__":

    # Host on 0.0.0.0 port 25642 for LAN, Web, Android & Windows accessibility
    port = int(os.environ.get("PORT", 25642))
    print(f"Starting WordN Server on http://0.0.0.0:{port}...")
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)

