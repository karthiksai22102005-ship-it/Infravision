# AI assistant setup

The Citizen API provides an optional OpenAI-compatible chat provider at `/api/v1/ai/chat`; the Flutter dashboard links to it from **AI Assistant**. AI is disabled until a provider key is set. The status endpoint returns `NOT_CONFIGURED` while disabled, and chat returns HTTP 503 rather than a sample or fabricated AI reply.

1. Copy `backend/.env.example` to `backend/.env` if needed.
2. Add the provider credential to `AI_API_KEY` locally. Never put it in Flutter source, APK assets, or chat.
3. Set `AI_BASE_URL` and `AI_MODEL` for the chosen OpenAI-compatible provider, then restart FastAPI.
4. Open the app dashboard and select **AI Assistant**. It supports English and the ten configured language codes; provider output quality depends on the model.

The endpoint only forwards the citizen's chat text and selected language. It does not load report history, photos, names, email addresses, or coordinates into the prompt.
