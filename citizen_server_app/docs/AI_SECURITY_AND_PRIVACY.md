# AI security and privacy notes

- Provider credentials stay on the backend in `AI_API_KEY`; the mobile and desktop clients only call the Citizen API.
- Chat requires citizen authentication, is rate-limited by the existing API limiter, and accepts messages up to 2,000 characters.
- Only the submitted message and language code are sent to the configured provider. The app does not silently add account details, complaints, evidence images, or GPS coordinates.
- When no provider key is configured, the API reports `NOT_CONFIGURED` and chat returns an explicit 503. There are no hardcoded model replies.
- The assistant provides reporting guidance; it cannot submit reports or promise that city services have taken action.
- Before public deployment, review the selected provider's data retention terms and configure HTTPS for the API and provider connection.
