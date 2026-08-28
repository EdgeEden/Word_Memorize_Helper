import sqlite3
import os
from typing import Dict, Any, List, Optional
from datetime import datetime

DB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
DB_PATH = os.path.join(DB_DIR, "wordn.db")

def get_connection() -> sqlite3.Connection:
    os.makedirs(DB_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_connection()
    with conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                created_at TEXT NOT NULL,
                last_active TEXT NOT NULL
            );
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS cards (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL,
                word TEXT NOT NULL,
                state INTEGER NOT NULL,
                stability REAL NOT NULL,
                difficulty REAL NOT NULL,
                reps INTEGER NOT NULL,
                lapses INTEGER NOT NULL,
                consecutive_correct INTEGER NOT NULL,
                last_review TEXT,
                due TEXT,
                due_step INTEGER NOT NULL DEFAULT -1,
                updated_at TEXT NOT NULL,
                UNIQUE(username, word)
            );
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_cards_user ON cards(username);")
    conn.close()

def login_or_register_user(username: str) -> Dict[str, Any]:
    username = username.strip().lower()
    now_str = datetime.utcnow().isoformat()
    conn = get_connection()
    try:
        with conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM users WHERE username = ?", (username,))
            row = cursor.fetchone()
            if row is None:
                cursor.execute(
                    "INSERT INTO users (username, created_at, last_active) VALUES (?, ?, ?)",
                    (username, now_str, now_str)
                )
                user_id = cursor.lastrowid
                is_new = True
            else:
                cursor.execute(
                    "UPDATE users SET last_active = ? WHERE username = ?",
                    (now_str, username)
                )
                user_id = row["id"]
                is_new = False
        return {"id": user_id, "username": username, "is_new": is_new}
    finally:
        conn.close()

def get_user_cards(username: str) -> Dict[str, Dict[str, Any]]:
    username = username.strip().lower()
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM cards WHERE username = ?", (username,))
        rows = cursor.fetchall()
        cards: Dict[str, Dict[str, Any]] = {}
        for row in rows:
            cards[row["word"]] = {
                "word": row["word"],
                "state": row["state"],
                "stability": row["stability"],
                "difficulty": row["difficulty"],
                "reps": row["reps"],
                "lapses": row["lapses"],
                "consecutiveCorrect": row["consecutive_correct"],
                "lastReview": row["last_review"],
                "due": row["due"],
                "dueStep": row["due_step"]
            }
        return cards
    finally:
        conn.close()

def upsert_user_cards(username: str, cards: Dict[str, Dict[str, Any]]) -> int:
    username = username.strip().lower()
    now_str = datetime.utcnow().isoformat()
    conn = get_connection()
    saved_count = 0
    try:
        with conn:
            cursor = conn.cursor()
            # Update user last_active
            cursor.execute("UPDATE users SET last_active = ? WHERE username = ?", (now_str, username))
            for word, card_data in cards.items():
                w = card_data.get("word", word)
                state = card_data.get("state", 0)
                stability = float(card_data.get("stability", 0.4))
                difficulty = float(card_data.get("difficulty", 5.0))
                reps = int(card_data.get("reps", 0))
                lapses = int(card_data.get("lapses", 0))
                consecutive_correct = int(card_data.get("consecutiveCorrect", 0))
                last_review = card_data.get("lastReview")
                due = card_data.get("due")
                due_step = int(card_data.get("dueStep", -1))

                cursor.execute("""
                    INSERT INTO cards (
                        username, word, state, stability, difficulty, reps, lapses,
                        consecutive_correct, last_review, due, due_step, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(username, word) DO UPDATE SET
                        state = excluded.state,
                        stability = excluded.stability,
                        difficulty = excluded.difficulty,
                        reps = excluded.reps,
                        lapses = excluded.lapses,
                        consecutive_correct = excluded.consecutive_correct,
                        last_review = excluded.last_review,
                        due = excluded.due,
                        due_step = excluded.due_step,
                        updated_at = excluded.updated_at;
                """, (
                    username, w, state, stability, difficulty, reps, lapses,
                    consecutive_correct, last_review, due, due_step, now_str
                ))
                saved_count += 1
        return saved_count
    finally:
        conn.close()

