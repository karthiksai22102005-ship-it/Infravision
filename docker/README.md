# InfraVision AI Docker Training & Inference Backend

This folder contains the containerized PyTorch and TFLite execution environment for **InfraVision**.

## Quick Start with Docker Desktop (Windows / macOS / Linux)

### 1. Start Container
```bash
docker-compose up -d
```
or run directly:
```bash
docker build -t infravision-trainer .
docker run -d -p 8000:8000 --name infravision-ai infravision-trainer
```

### 2. Verify Health
Open your browser or run:
```bash
curl http://localhost:8000/health
```

### 3. API Endpoints
- `GET /health`: Health and hardware device telemetry.
- `POST /train`: Asynchronous real-time model training with live epoch logs.
- `POST /classify`: Multi-class image defect prediction with confidence and severity scores.
- `GET /models`: List and export compiled `.tflite` (Android APK ready) and `.onnx` models.

## Offline Standalone Mode
The InfraVision Flutter workstation automatically includes a built-in on-device AI classification and training engine. If Docker Desktop is not running, the application seamlessly operates 100% locally on your computer.
