# Veylola Voice

A mobile-friendly, voice-first assistant web prototype.

## Features
- Responsive dark interface with animated listening orb
- Browser speech recognition when supported
- Spoken replies using the browser's text-to-speech engine
- Text chat and a few starter commands (greetings, date, time, motivation)
- No API key required for this starter demo

## Run locally
Because microphone access is restricted by many browsers on plain HTTP, use HTTPS when deployed. You can also open `index.html` locally, although speech recognition support may vary.

This is a static site: deploy the repository with GitHub Pages, or use any static hosting provider.

## Important limitations
This version does **not** yet connect to a real AI model. Unknown questions receive a clear placeholder reply. Browser speech recognition may rely on an online service and requires microphone permission. It is not an always-listening wake-word assistant, and a web page cannot freely launch other phone apps.

## Connect an AI backend next
Create a server endpoint such as `POST /api/chat` that accepts `{ "message": "..." }` and returns `{ "reply": "..." }`. Then update the `respond()` function in `index.html` to call that endpoint. Keep private API keys on the server, never inside browser JavaScript.

## License
Choose a license before distributing this project.
