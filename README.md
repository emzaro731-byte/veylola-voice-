# Veylola Voice

Veylola Voice is a JARVIS-inspired assistant project with a Flutter Android app and an earlier browser prototype.

## Flutter Android app

The Flutter app includes:
- Dark futuristic assistant interface
- Speech recognition and spoken responses
- Optional “Hey Veylola” wake phrase while the app is open and microphone listening is enabled
- Starter commands for time, date, Google search, and opening supported websites
- Optional chat request to the Veylola backend

## Build an APK on GitHub

1. Open the repository's **Actions** tab.
2. Select **Build Veylola Voice APK**.
3. Tap **Run workflow** and wait for the workflow to finish.
4. Open the successful workflow run and download the **vey­lola-voice-release-apk** artifact.
5. Extract the ZIP and install `app-release.apk` on your Android phone.

A push to the Flutter app files also triggers the build workflow.

## Voice and phone limitations

Android will request microphone permission. Speech recognition availability depends on the phone's speech services and language settings. Wake-word listening works only while the app is open; Android may stop microphone use in the background. This starter app opens supported websites externally and cannot freely control every app, setting, or device function.

## AI connection

The app currently attempts to call `https://veylola-voice-api.onrender.com/api/chat`. The backend must be deployed and return JSON such as `{"reply":"Hello"}`. Configure private AI credentials on the backend, never in the Flutter app. If the endpoint is unavailable, basic commands still work and the app explains that its AI brain is not connected.

## Web prototype

The original `index.html` browser prototype is still included.
