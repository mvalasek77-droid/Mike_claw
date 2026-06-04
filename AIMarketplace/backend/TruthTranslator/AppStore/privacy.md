# Privacy Notes

ChadDrop does not collect data in the default offline configuration.

When an AI proxy URL is configured, pasted text is sent to that proxy only to generate the decode result. Do not log raw user messages in the proxy. The included Cloudflare Worker scaffold forwards text to OpenAI and returns structured JSON to the app.

Recommended App Store privacy answers for the default app:
- Data collection: None.
- Tracking: No.
- Third-party advertising: No.

Recommended answers when AI proxy is enabled:
- User Content may be processed to provide app functionality.
- Do not link user content to identity unless the production backend adds accounts.
- Tracking: No.

The privacy manifest declares no required-reason API usage and no tracking domains.
