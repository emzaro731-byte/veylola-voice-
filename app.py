import os
from datetime import datetime
from flask import Flask, jsonify, request
from flask_cors import CORS
import requests

app = Flask(__name__)
CORS(app)

AI_API_URL = os.getenv("AI_API_URL", "").strip()
AI_API_KEY = os.getenv("AI_API_KEY", "").strip()
AI_MODEL = os.getenv("AI_MODEL", "").strip()

def local_reply(message):
    text = message.lower().strip()
    if any(text.startswith(g) for g in ("hi", "hello", "hey", "good morning", "good afternoon", "good evening")):
        return "Hello! 💜 I'm Veylola Voice. What would you like help with today?"
    if "your name" in text:
        return "I'm Veylola Voice, your voice-first assistant."
    if "time" in text:
        return "The server time is " + datetime.now().strftime("%I:%M %p") + "."
    if "date" in text or "today" in text:
        return "Today is " + datetime.now().strftime("%A, %B %d, %Y") + "."
    if "motivat" in text:
        return "Keep going, one small step at a time. You don't have to finish everything today—you just have to begin. 💜"
    if "fun fact" in text:
        return "Fun fact: octopuses have three hearts."
    if "what can you do" in text or "help" in text:
        return "I can chat, answer simple built-in questions, and speak replies aloud. Configure an AI-compatible endpoint to enable broader online AI answers."
    return "I'm in fallback mode right now, so I can only answer simple built-in questions. Configure AI_API_URL, AI_API_KEY, and AI_MODEL on the server for online AI answers."

@app.get("/")
def home():
    return jsonify({"app": "Veylola Voice API", "status": "ok"})

@app.get("/health")
def health():
    return jsonify({"status": "ok", "online_ai_configured": bool(AI_API_URL and AI_API_KEY and AI_MODEL)})

@app.post("/api/chat")
def chat():
    data = request.get_json(silent=True) or {}
    message = str(data.get("message", "")).strip()
    history = data.get("history", [])
    if not message:
        return jsonify({"error": "Please send a message."}), 400

    if AI_API_URL and AI_API_KEY and AI_MODEL:
        try:
            messages = [{"role": "system", "content": "You are Veylola, a helpful, friendly assistant. Keep answers clear and concise."}]
            if isinstance(history, list):
                for item in history[-10:]:
                    if isinstance(item, dict) and item.get("role") in ("user", "assistant") and isinstance(item.get("content"), str):
                        messages.append({"role": item["role"], "content": item["content"][:4000]})
            messages.append({"role": "user", "content": message[:4000]})
            response = requests.post(
                AI_API_URL,
                headers={"Authorization": f"Bearer {AI_API_KEY}", "Content-Type": "application/json"},
                json={"model": AI_MODEL, "messages": messages, "temperature": 0.7},
                timeout=35,
            )
            response.raise_for_status()
            payload = response.json()
            answer = payload["choices"][0]["message"]["content"]
            if isinstance(answer, list):
                answer = " ".join(part.get("text", "") for part in answer if isinstance(part, dict))
            if isinstance(answer, str) and answer.strip():
                return jsonify({"reply": answer.strip(), "mode": "online"})
        except Exception:
            app.logger.exception("Online AI request failed; using fallback.")

    return jsonify({"reply": local_reply(message), "mode": "fallback"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
