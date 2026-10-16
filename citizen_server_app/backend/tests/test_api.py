import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"
os.environ["EVIDENCE_DIR"] = f"{_tmp}/ev"
os.environ["INSPECTOR_API_KEY"] = "insp-test-key"
os.environ["JWT_SECRET"] = "test-secret-for-isolated-api-tests-32+"
os.environ["ENVIRONMENT"] = "test"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.api import routes  # noqa: E402
from app.main import app  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
COMPLAINT = {"category_code": "pothole", "description": "Large pothole causing traffic issues",
             "latitude": 16.71, "longitude": 81.10, "accuracy_m": 8}
INSP = {"X-Inspector-Key": "insp-test-key"}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def _reset_rate_limit():
    routes._hits.clear()


def register(client, email):
    r = client.post("/api/v1/auth/register", json={"email": email, "full_name": "Test User", "password": "password123"})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def create(client, h, key="key-12345678"):
    return client.post("/api/v1/complaints", json=COMPLAINT, headers={**h, "Idempotency-Key": key})


def test_health_and_ready(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").status_code == 200


def test_categories_seeded(client):
    codes = [c["code"] for c in client.get("/api/v1/categories").json()]
    assert "pothole" in codes and len(codes) == 9


def test_auth_flow_and_bad_login(client):
    h = register(client, "a@example.com")
    assert client.get("/api/v1/me", headers=h).json()["email"] == "a@example.com"
    assert client.post("/api/v1/auth/login", json={"email": "a@example.com", "password": "wrongwrong"}).status_code == 401
    assert client.post("/api/v1/auth/login", json={"email": "a@example.com", "password": "password123"}).status_code == 200
    assert client.get("/api/v1/me").status_code == 401


def test_complaint_validation(client):
    h = register(client, "v@example.com")
    bad = {**COMPLAINT, "latitude": 123}
    assert client.post("/api/v1/complaints", json=bad, headers={**h, "Idempotency-Key": "key-abcdefgh"}).status_code == 422
    bad = {**COMPLAINT, "category_code": "nope"}
    assert client.post("/api/v1/complaints", json=bad, headers={**h, "Idempotency-Key": "key-abcdefgh"}).status_code == 422


def test_idempotent_create(client):
    h = register(client, "i@example.com")
    r1, r2 = create(client, h, "idem-key-0001"), create(client, h, "idem-key-0001")
    assert r1.status_code == 201 and r2.status_code == 200
    assert r1.json()["reference"] == r2.json()["reference"]
    assert len(client.get("/api/v1/complaints", headers=h).json()) == 1


def test_ownership_enforced(client):
    a, b = register(client, "own1@example.com"), register(client, "own2@example.com")
    ref = create(client, a, "own-key-0001").json()["reference"]
    assert client.get(f"/api/v1/complaints/{ref}", headers=b).status_code == 404
    assert client.get(f"/api/v1/complaints/{ref}/report.pdf", headers=b).status_code == 404
    assert client.get(f"/api/v1/complaints/{ref}", headers=a).status_code == 200


def test_evidence_validation_and_upload(client):
    h = register(client, "e@example.com")
    ref = create(client, h, "evi-key-0001").json()["reference"]
    url = f"/api/v1/complaints/{ref}/evidence"
    assert client.post(url, files={"file": ("x.txt", b"hello", "text/plain")}, headers=h).status_code == 415
    ok = client.post(url, files={"file": ("p.png", PNG, "image/png")}, headers=h)
    assert ok.status_code == 201
    assert client.get(f"{url}/{ok.json()['id']}", headers=h).content == PNG


def test_inspector_auth_and_transitions(client):
    h = register(client, "t@example.com")
    ref = create(client, h, "trn-key-0001").json()["reference"]
    url = f"/api/v1/inspector/complaints/{ref}/status"
    assert client.post(url, json={"status": "under_review"}).status_code == 403
    assert client.post(url, json={"status": "under_review"}, headers={"X-Inspector-Key": "bad"}).status_code == 403
    assert client.post(url, json={"status": "resolved"}, headers=INSP).status_code == 409  # illegal jump
    r = client.post(url, json={"status": "under_review", "inspector_note": "SECRET NOTE"}, headers=INSP)
    assert r.status_code == 200 and r.json()["status"] == "under_review"
    notes = client.get("/api/v1/notifications", headers=h).json()
    assert any("Under Review" in n["title"] for n in notes)
    assert "SECRET NOTE" not in client.get(f"/api/v1/complaints/{ref}", headers=h).text


def test_pdf_generation_hides_inspector_notes(client):
    h = register(client, "p@example.com")
    ref = create(client, h, "pdf-key-0001").json()["reference"]
    client.post(f"/api/v1/inspector/complaints/{ref}/status",
                json={"status": "under_review", "inspector_note": "PRIVATE-XYZ"}, headers=INSP)
    r = client.get(f"/api/v1/complaints/{ref}/report.pdf", headers=h)
    assert r.status_code == 200 and r.content.startswith(b"%PDF")
    assert b"PRIVATE-XYZ" not in r.content
    assert len(r.content) > 1500


def test_nearby(client):
    h = register(client, "n@example.com")
    create(client, h, "nby-key-0001")
    near = client.get("/api/v1/complaints/nearby", params={"lat": 16.71, "lng": 81.10}, headers=h).json()
    far = client.get("/api/v1/complaints/nearby", params={"lat": 28.6, "lng": 77.2}, headers=h).json()
    assert len(near) >= 1 and far == []


def test_rate_limit_login(client):
    codes = [client.post("/api/v1/auth/login", json={"email": "z@example.com", "password": "whatever1"}).status_code
             for _ in range(12)]
    assert 429 in codes


def test_ai_status_unconfigured(client):
    r = client.get("/api/v1/ai/status")
    assert r.status_code == 200
    assert r.json()["status"] == "NOT_CONFIGURED"
    # When unconfigured, chat raises 503
    chat = client.post("/api/v1/ai/chat", json={"message": "How do I report a pothole?", "language": "en"})
    assert chat.status_code == 503
