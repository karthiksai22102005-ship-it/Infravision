# API Documentation

Current endpoints (from code, prefix `/api/v1`): POST auth/register, auth/login; GET me, categories; POST complaints (header Idempotency-Key); GET complaints, complaints/nearby, complaints/{ref}; POST/GET complaints/{ref}/evidence[/{id}]; GET complaints/{ref}/report.pdf; GET notifications; POST notifications/{id}/read; POST inspector/complaints/{ref}/status (X-Inspector-Key). OpenAPI is auto-served at /docs. Missing: pagination, report status/list endpoints, logout, refresh, regenerate.
