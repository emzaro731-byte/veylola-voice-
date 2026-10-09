# Veylola Voice

Veylola Voice is a JARVIS-inspired assistant project with a Flutter Android app and an earlier browser prototype.

## Flutter Android app

The Flutter app includes:
- Dark futuristic assistant interface
- Speech recognition and spoken responses
- Optional Accessibility Service scaffold with a shortcut to Android Accessibility settings; it must be enabled manually and does not read screen content or perform gestures
- Optional “Hey Veylola” wake phrase using an Android microphone foreground service, restart retries, a persistent notification, and a user-approved battery-optimization exemption request
- Starter commands for time, date, Google search, opening supported apps and websites, opening Wi-Fi/Bluetooth settings, and preparing calls/texts
- Recent conversation history sent to the backend for contextual AI replies
- Optional chat request to the Veylola backend

## Build an APK on GitHub

1. Open the repository's **Actions** tab.
2. Select **Build Veylola Voice APK**.
3. Tap **Run workflow** and wait for the workflow to finish.
4. Open the successful workflow run and download the **vey­lola-voice-release-apk** artifact.
5. Extract the ZIP and install `app-release.apk` on your Android phone.

A push to the Flutter app files also triggers the build workflow.

## Optional Accessibility Service

Tap the accessibility-person icon in the app bar to open Android's Accessibility settings. Find **Veylola Voice** under Downloaded apps or Installed services and enable it yourself if you choose. Android will show its own confirmation. This starter service intentionally does not read screen content, click controls, or perform gestures, and it cannot be silently made the default. Only enable accessibility services you trust.

## Voice commands

Try these examples:
- `open YouTube`, `open WhatsApp`, `open Settings`, or `open Camera`
- `search weather tomorrow`
- `call 08012345678` — opens the dialer with the number; the user must tap Call
- `text 08012345678 I am on my way` — opens a message draft; the user must tap Send
- `Wi-Fi settings` or `Bluetooth settings` — opens Android settings; the user changes the setting
- `what time is it`, `what is today's date`, or `help`

Android will request microphone permission. Speech recognition availability depends on the phone's speech services and language settings. The foreground service uses Android's microphone foreground-service type, retry backoff, and a persistent notification. Use the battery icon in the app to open Android's battery-optimization exemption prompt; you must approve it yourself. On some devices, also open Settings > Apps > Veylola Voice > Battery and choose Unrestricted, allow notifications and microphone access, and allow background activity if offered. If Android detects the wake phrase while the app is backgrounded, Veylola posts a notification for you to tap; Android can block an app from forcibly bringing itself to the foreground. The OS, speech service, manufacturer power manager, force-stop state, or revoked permissions can still stop listening. This cannot be guaranteed to behave like a built-in system hotword assistant. The app cannot silently place calls, send texts, or freely change protected Android settings.

## Groq AI connection through Render

The Flutter app sends chat requests to `https://veylola-voice-api.onrender.com/api/chat`. The Flask backend now defaults to Groq's OpenAI-compatible endpoint and the `llama-3.3-70b-versatile` model.

1. Open the Render dashboard and select the `veylola-voice-api` web service.
2. Open **Environment**.
3. Add `GROQ_API_KEY` with your secret key from the Groq Console.
4. Keep the key private: do not paste it into Flutter, GitHub files, screenshots, or public messages.
5. Save changes and let Render redeploy the service.
6. Open `https://veylola-voice-api.onrender.com/health`. It should show `"online_ai_configured": true` when the key and settings are present.

Render blueprint defaults are `AI_API_URL=https://api.groq.com/openai/v1/chat/completions` and `AI_MODEL=llama-3.3-70b-versatile`. If the service was created before these defaults were added, check the Environment page and set them there if missing. You can use a different Groq-supported model by changing `AI_MODEL`. The API key stays server-side. If Groq is unavailable or the key/model is invalid, the backend logs the error and returns its built-in fallback reply.

## Web prototype

The original `index.html` browser prototype is still included.
