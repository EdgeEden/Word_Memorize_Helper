from fastapi.testclient import TestClient
from main import app
from database import init_db

def test_api():
    init_db()
    client = TestClient(app)

    # 1. Health check
    res = client.get("/api/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"
    print("[PASS] /api/health")

    # 2. Login new user
    res = client.post("/api/login", json={"username": "test_user_1"})
    assert res.status_code == 200
    data = res.json()
    assert data["username"] == "test_user_1"
    assert data["is_new"] is True
    print("[PASS] /api/login new user")

    # 3. Sync cards
    sample_cards = {
        "influence": {
            "word": "influence",
            "state": 2,
            "stability": 3.5,
            "difficulty": 4.2,
            "reps": 3,
            "lapses": 0,
            "consecutiveCorrect": 3,
            "lastReview": "2026-08-28T00:00:00.000",
            "due": "2026-08-31T00:00:00.000",
            "dueStep": -1
        },
        "abandon": {
            "word": "abandon",
            "state": 3,
            "stability": 0.4,
            "difficulty": 6.8,
            "reps": 2,
            "lapses": 1,
            "consecutiveCorrect": 0,
            "lastReview": "2026-08-28T01:00:00.000",
            "due": "2026-08-28T01:05:00.000",
            "dueStep": 3
        }
    }
    res = client.post("/api/cards/sync", json={"username": "test_user_1", "cards": sample_cards})
    assert res.status_code == 200
    assert res.json()["status"] == "ok"
    assert res.json()["saved_count"] == 2
    print("[PASS] /api/cards/sync")

    # 4. Fetch cards
    res = client.get("/api/cards?username=test_user_1")
    assert res.status_code == 200
    cards_data = res.json()
    assert "influence" in cards_data["cards"]
    assert "abandon" in cards_data["cards"]
    assert cards_data["cards"]["influence"]["stability"] == 3.5
    print("[PASS] /api/cards fetch")

    # 5. Login existing user returns stored cards
    res = client.post("/api/login", json={"username": "test_user_1"})
    assert res.status_code == 200
    data = res.json()
    assert data["is_new"] is False
    assert "influence" in data["cards"]
    print("[PASS] /api/login existing user with cards")

    print("\nALL SERVER TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    test_api()

