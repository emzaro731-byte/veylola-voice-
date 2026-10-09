# Seri Voice

Seri is a voice-first Android assistant built with Flutter and a Flask API hosted on Render. It combines a liquid-glass inspired dark interface, speech input/output, local Android shortcuts, and optional online AI chat.

## Features
- Voice input and spoken replies using Android speech services and Flutter TTS.
- Online AI chat through the Render backend; the Groq secret stays on the server.
- Server health indicator with a manual refresh button.
- Recent conversation context sent with chat requests.
- Quick actions for opening supported apps and websites, Google search, time/date, Wi-Fi/Bluetooth settings, call dialer, and SMS drafts.
- Optional wake-word foreground service. Say "Hey Seri" or the legacy phrase "Hey Veylola"; Android may still restrict background microphone access.
- Optional accessibility-service scaffold that must be enabled manually in Android settings. It does not read screen content or perform gestures.

## Build the Android APK
1. Open the repository's Actions tab.
2. Choose "Build Seri Voice APK".
3. Tap "Run workflow" and wait for it to finish.
4. Open the successful run and download the "seri-voice-release-apk" artifact.
5. Extract the ZIP and install app-release.apk.

The workflow generates the required Android project and native background-service files, checks Dart formatting, analyzes the Flutter app, validates Python syntax, builds a release APK, and uploads the artifact.

## Connect online AI with Render + Groq
1. Open the Render dashboard: https://dashboard.render.com/
2. Select the seri-muob web service and open Environment.
3. Set these variables:
   - GROQ_API_KEY: your private key from the Groq Console at https://console.groq.com/keys
   - AI_API_URL: https://api.groq.com/openai/v1/chat/completions
   - AI_MODEL: llama-3.3-70b-versatile
4. Save changes and wait for the service to redeploy.
5. Test https://seri-muob.onrender.com/health. The response should show "online_ai_configured": true.

Never put the Groq key in Flutter code, GitHub files, or screenshots. Keep it in Render's Environment settings only.

## API
- GET / — service status.
- GET /health — safe health/configuration status; does not reveal secrets.
- POST /api/chat or POST /chat — send JSON such as {"message":"Hello","history":[]}.

A successful chat response contains reply and mode (online or fallback). If the AI provider is unavailable, the API returns a built-in fallback answer instead of exposing credentials or crashing.

## Android permissions and safety
Android requires the user to grant microphone permission. Background listening depends on Android's speech services, notification permission, battery management, and manufacturer-specific restrictions; continuous wake-word operation cannot be guaranteed. The app cannot silently bypass Android protections. Saying “call my mum” (or “call mum/mom/mummy/mother”) looks up a matching saved contact and starts the call after you grant Contacts and Phone permissions. Calls to a number still open the dialer for review, and texts open a draft for the user to send. Wi-Fi and Bluetooth commands open the relevant settings rather than changing protected settings invisibly.

## Web prototype
The original index.html browser prototype remains in the repository.
