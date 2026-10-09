# Veylola Voice

Veylola Voice is a JARVIS-inspired assistant project with a Flutter Android app and an earlier browser prototype.

## Flutter Android app

The Flutter app includes:
- Dark futuristic assistant interface
- Speech recognition and spoken responses
- Optional “Hey Veylola” wake phrase; background service behavior depends on Android version, permissions, speech service, and battery policy
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

## Voice commands

Try these examples:
- `open YouTube`, `open WhatsApp`, `open Settings`, or `open Camera`
- `search weather tomorrow`
- `call 08012345678` — opens the dialer with the number; the user must tap Call
- `text 08012345678 I am on my way` — opens a message draft; the user must tap Send
- `Wi-Fi settings` or `Bluetooth settings` — opens Android settings; the user changes the setting
- `what time is it`, `what is today's date`, or `help`

Android will request microphone permission. Speech recognition availability depends on the phone's speech services and language settings. The foreground service requests background wake-word listening, but Android versions, microphone permissions, manufacturer battery policies, speech-service behavior, and restrictions on launching apps from the background can prevent reliable always-on listening. This is not guaranteed to work like a system-level hotword assistant. The app cannot silently place calls, send texts, or freely change protected Android settings.

## AI connection

The app currently attempts to call `https://veylola-voice-api.onrender.com/api/chat`. The backend must be deployed and return JSON such as `{"reply":"Hello"}`. Configure private AI credentials on the backend, never in the Flutter app. If the endpoint is unavailable, basic commands still work and the app explains that its AI brain is not connected.

## Web prototype

The original `index.html` browser prototype is still included.
