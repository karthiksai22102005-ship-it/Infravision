"""Optional OpenAI-compatible AI provider. No canned responses are returned."""
import httpx

from app.core.config import get_settings


class AIProviderNotConfigured(Exception):
    pass


def assistant_status() -> dict:
    settings = get_settings()
    provider = (settings.ai_provider or '').strip().lower()
    requires_api_key = provider != 'ollama'
    ready = bool(
        (not requires_api_key or (settings.ai_api_key or "").strip())
        and (settings.ai_base_url or "").strip()
        and (settings.ai_model or "").strip()
    )
    return {
        "status": "READY" if ready else "NOT_CONFIGURED",
        "provider": settings.ai_provider if ready else None,
        "model": settings.ai_model if ready else None,
    }


def ask_assistant(message: str, language: str) -> str:
    settings = get_settings()
    api_key = (settings.ai_api_key or "").strip()
    base_url = (settings.ai_base_url or "").strip()
    model = (settings.ai_model or "").strip()
    provider = (settings.ai_provider or '').strip().lower()
    if (provider != 'ollama' and not api_key) or not base_url or not model:
        raise AIProviderNotConfigured
    if provider == 'ollama' and not base_url.rstrip('/').endswith('/v1'):
        base_url = f"{base_url.rstrip('/')}/v1"
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    response = httpx.post(
        f"{base_url.rstrip('/')}/chat/completions",
        headers=headers,
        json={"model": model, "temperature": 0.2,
              "messages": [
                  {"role": "system", "content": (
                      "You are InfraVision Citizen's civic reporting assistant. Help with reporting "
                      "public infrastructure issues and explain app workflows. Do not claim a report "
                      "was filed or provide emergency response. Reply in language code " + language + ".")},
                  {"role": "user", "content": message}],
        }, timeout=25.0,
    )
    response.raise_for_status()
    answer = response.json()["choices"][0]["message"]["content"]
    if not isinstance(answer, str) or not answer.strip():
        raise ValueError("AI provider returned an empty answer")
    return answer.strip()
