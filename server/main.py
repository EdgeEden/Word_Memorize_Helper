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
    "version": "1.0.4",
    "version_code": 5,
    "min_supported_version_code": 1,
    "title": "WordN v1.0.4 全新体验升级",
    "release_notes": "1. 📚 支持导入自定义词库：多端适配 CSV 词库上传与解析，独立隔离错题本与多端云同步\n2. ⚡ 安卓后台下载与通知栏增强：基于系统原生 DownloadManager，切出应用/锁屏持续稳定下载，通知栏与应用内进度实时同步\n3. 🛡️ 强制更新防护与顶部下载指示：顶部 AppBar 实时显示下载进度与状态，强化重要版本更新防护\n4. 🎨 界面与体验优化：重构偏好设置与 AI 判定面板，彻底消除 Web 渲染与排版异常",
    "apk_url": "/api/download/apk",
    "windows_url": "/api/download/windows",
    "force_update": False,
    "pub_date": "2026-08-31T18:15:00Z"
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

