import os
import uvicorn
from datetime import datetime
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from database import init_db, login_or_register_user, get_user_cards, upsert_user_cards
from models import LoginRequest, LoginResponse, SyncRequest, SyncResponse, HealthResponse

app = FastAPI(
    title="WordN Vocabulary Sync API",
    description="Backend API for WordN FSRS Vocabulary and Wrong Words Synchronization",
    version="1.0.0"
)

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
    return {"status": "ok", "version": "1.0.0"}

@app.post("/api/login", response_model=LoginResponse)
def login_or_register(payload: LoginRequest):
    username = payload.username.strip().lower()
    if not username:
        raise HTTPException(status_code=400, detail="Username cannot be empty")

    user_info = login_or_register_user(username)
    cards = get_user_cards(username)
    return {
        "id": user_info["id"],
        "username": user_info["username"],
        "is_new": user_info["is_new"],
        "cards": cards
    }

@app.get("/api/cards")
def fetch_cards(username: str = Query(..., min_length=1)):
    clean_username = username.strip().lower()
    cards = get_user_cards(clean_username)
    return {
        "username": clean_username,
        "cards": cards,
        "count": len(cards),
        "updated_at": datetime.utcnow().isoformat()
    }

@app.post("/api/cards/sync", response_model=SyncResponse)
def sync_cards(payload: SyncRequest):
    clean_username = payload.username.strip().lower()
    if not clean_username:
        raise HTTPException(status_code=400, detail="Username cannot be empty")

    # Ensure user exists
    login_or_register_user(clean_username)
    saved = upsert_user_cards(clean_username, payload.cards)
    return {
        "status": "ok",
        "saved_count": saved,
        "updated_at": datetime.utcnow().isoformat()
    }

if __name__ == "__main__":
    # Host on 0.0.0.0 port 25642 for LAN, Web, Android & Windows accessibility
    port = int(os.environ.get("PORT", 25642))
    print(f"Starting WordN Server on http://0.0.0.0:{port}...")
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)

