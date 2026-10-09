import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const VeylolaApp());

class VeylolaApp extends StatelessWidget {
  const VeylolaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Veylola Voice',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF070B14),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF69D9FF), brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const AssistantPage(),
  );
}

class ChatLine {
  ChatLine(this.text, this.isUser);
  final String text;
  final bool isUser;
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> with WidgetsBindingObserver {
  static const MethodChannel _backgroundChannel = MethodChannel('com.veylola.veylola_voice/background');
  Future<void> _setBackgroundListening(bool enabled) async {
    try { await _backgroundChannel.invokeMethod(enabled ? 'start' : 'stop'); }
    catch (_) { if (mounted) _add('Background listening service could not start. Check microphone permission and rebuild the APK.', false); }
  }
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _tts = FlutterTts();
  final _speech = stt.SpeechToText();
  final List<ChatLine> _messages = [
    ChatLine('Veylola online. Tap the microphone and say “Hey Veylola”, or type a command.', false),
  ];
  bool _ready = false, _listening = false, _busy = false, _wakeMode = false;
  String _status = 'READY';
  // Optional: set this to your deployed Veylola backend URL.
  static const String aiEndpoint = 'https://veylola-voice-api.onrender.com/api/chat';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVoice();
    _tts.setSpeechRate(0.47);
    _tts.setPitch(0.92);
  }

  Future<void> _initVoice() async {
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (!mounted) return;
        setState(() {
          _listening = _speech.isListening;
          if (!_listening && _status == 'LISTENING') _status = 'READY';
        });
        if (_wakeMode && !_speech.isListening) {
          Future.delayed(const Duration(milliseconds: 450), () {
            if (mounted && _wakeMode) _listen();
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() { _listening = false; _status = 'VOICE UNAVAILABLE'; });
      },
    );
    if (mounted) setState(() => _ready = ok);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  void _add(String text, bool user) {
    setState(() => _messages.add(ChatLine(text, user)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _listen() async {
    if (!_ready) {
      await _initVoice();
      if (!_ready) {
        _add('Please allow microphone permission and check that speech recognition is available on this phone.', false);
        return;
      }
    }
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() { _listening = false; _status = 'READY'; });
      return;
    }
    await _tts.stop();
    setState(() { _listening = true; _status = _wakeMode ? 'WAKE WORD ACTIVE' : 'LISTENING'; });
    await _speech.listen(
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        if (!mounted) return;
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        if (_wakeMode && !words.toLowerCase().contains('hey veylola') &&
            !words.toLowerCase().contains('hey vey')) return;
        final command = words.replaceFirst(RegExp(r'^(hey\s+veylola|hey\s+vey)\s*[, ]*', caseSensitive: false), '').trim();
        if (result.finalResult && command.isNotEmpty) {
          setState(() => _input.text = command);
          _handle(command);
        }
      },
      localeId: 'en_NG',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wakeMode && !_speech.isListening) {
      Future.delayed(const Duration(milliseconds: 700), () { if (mounted && _wakeMode && !_speech.isListening) _listen(); });
    }
  }

  Future<void> _toggleWake() async {
    setState(() => _wakeMode = !_wakeMode);
    if (_wakeMode) {
      await _setBackgroundListening(true);
      _add('Background service requested. Android will show an ongoing notification. Wake-word detection may depend on Android speech-service and battery settings.', false);
      // Native Android foreground service listens for the wake phrase while the app is backgrounded.
    } else {
      await _setBackgroundListening(false);
      await _speech.stop();
      setState(() { _listening = false; _status = 'READY'; });
      _add('Wake-word mode paused.', false);
    }
  }

  Future<void> _speak(String text) async {
    try { await _tts.stop(); await _tts.speak(text); } catch (_) {}
  }

  Future<void> _handle(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    _add(text, true);
    final q = text.toLowerCase();
    setState(() { _busy = true; _status = 'THINKING'; });
    String? local;
    if (RegExp(r'\b(hello|hi|hey)\b').hasMatch(q)) local = 'Hello. Veylola is ready to help.';
    else if (q.contains('your name')) local = 'I am Veylola Voice, your personal assistant.';
    else if (q.contains('time')) local = 'The time is ${TimeOfDay.now().format(context)}.';
    else if (q.contains('date') || q.contains('day is it')) {
      final d = DateTime.now();
      local = 'Today is ${d.day} / ${d.month} / ${d.year}.';
    } else if (q.contains('stop talking') || q == 'stop') {
      await _tts.stop(); local = 'Voice output stopped.';
    } else if (q.contains('clear chat')) {
      setState(() => _messages.clear()); local = 'Chat cleared.';
    } else if (q.startsWith('call ') || q.startsWith('dial ')) {
      final number = text.replaceFirst(RegExp(r'^(call|dial)\s+', caseSensitive: false), '').trim();
      local = await _openDialer(number);
    } else if (q.startsWith('text ') || q.startsWith('message ')) {
      local = await _composeText(text.replaceFirst(RegExp(r'^(text|message)\s+', caseSensitive: false), '').trim());
    } else if (q.contains('wifi settings') || q.contains('wi-fi settings') || q == 'turn on wifi' || q == 'turn off wifi') {
      local = await _openSystemSettings('android.settings.WIFI_SETTINGS', 'Wi-Fi settings');
    } else if (q.contains('bluetooth settings') || q == 'turn on bluetooth' || q == 'turn off bluetooth') {
      local = await _openSystemSettings('android.settings.BLUETOOTH_SETTINGS', 'Bluetooth settings');
    } else if (q == 'help' || q.contains('what commands') || q.contains('what can you do')) {
      local = 'Try: “open YouTube”, “open Settings”, “search football news”, “call 080…”, “text 080… hello”, “Wi-Fi settings”, “Bluetooth settings”, “what time is it”, or ask me a question. Calls and texts open a screen for you to review; I do not send them automatically.';
    } else if (q.startsWith('open ') || q.startsWith('launch ')) {
      final target = q.replaceFirst(RegExp(r'^(open|launch)\s+'), '').trim();
      local = await _openTarget(target);
    } else if (q.startsWith('search ')) {
      final term = text.substring(7).trim();
      final uri = Uri.https('www.google.com', '/search', {'q': term});
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      local = 'Searching Google for $term.';
    } else {
      local = await _askAI(text);
    }
    if (mounted && local != null && local.isNotEmpty) {
      _add(local, false);
      await _speak(local);
    }
    if (mounted) setState(() { _busy = false; _status = _wakeMode ? 'WAKE WORD ACTIVE' : 'READY'; });
  }

  Future<String> _openDialer(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (cleaned.length < 3) return 'Please say “call” followed by a phone number.';
    try {
      await AndroidIntent(action: 'android.intent.action.DIAL', data: 'tel:$cleaned').launch();
      return 'I opened the dialer with $cleaned. Review the number and tap Call yourself.';
    } catch (_) {
      return 'I could not open the phone dialer on this device.';
    }
  }

  Future<String> _composeText(String details) async {
    final match = RegExp(r'^([+0-9][0-9 +()-]{2,})\s+(.+)').firstMatch(details);
    if (match == null) return 'Use “text phone-number message”, for example: text 08012345678 I am on my way.';
    final number = match.group(1)!.replaceAll(RegExp(r'[^0-9+]'), '');
    final message = match.group(2)!.trim();
    try {
      await AndroidIntent(
        action: 'android.intent.action.SENDTO',
        data: Uri(scheme: 'smsto', path: number).toString(),
        arguments: <String, dynamic>{'sms_body': message},
      ).launch();
      return 'I opened a text draft to $number. Please review it and tap Send yourself.';
    } catch (_) {
      return 'I could not open the messaging app on this device.';
    }
  }

  Future<String> _openSystemSettings(String action, String label) async {
    try {
      await AndroidIntent(action: action).launch();
      return 'Opening $label. Android requires you to change the setting yourself.';
    } catch (_) {
      return 'I could not open $label on this device.';
    }
  }

  Future<String> _openTarget(String target) async {
    final appPackages = <String, String>{
      'youtube': 'com.google.android.youtube',
      'chrome': 'com.android.chrome',
      'google maps': 'com.google.android.apps.maps',
      'maps': 'com.google.android.apps.maps',
      'phone': 'com.google.android.dialer',
      'dialer': 'com.google.android.dialer',
      'settings': 'com.android.settings',
      'camera': 'com.android.camera2',
      'calculator': 'com.google.android.calculator',
      'gmail': 'com.google.android.gm',
      'whatsapp': 'com.whatsapp',
      'telegram': 'org.telegram.messenger',
    };
    // Prefer an installed native app when a clear app command was used.
    final appKey = appPackages.keys
        .where((k) => target == k || target == 'the $k')
        .firstWhere((_) => true, orElse: () => '');
    if (appKey.isNotEmpty) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          category: 'android.intent.category.LAUNCHER',
          package: appPackages[appKey],
        );
        await intent.launch();
        return 'Opening $appKey.';
      } catch (_) {
        return 'I could not launch $appKey. It may not be installed or Android may block the request.';
      }
    }
    final sites = <String, String>{
      'youtube': 'https://youtube.com',
      'google': 'https://google.com',
      'gmail': 'https://mail.google.com',
      'facebook': 'https://facebook.com',
      'instagram': 'https://instagram.com',
      'tiktok': 'https://tiktok.com',
      'whatsapp': 'https://wa.me/',
      'github': 'https://github.com',
      'veylola shop': 'https://veylola-shop.onrender.com',
      'browser': 'https://google.com',
    };
    final key = sites.keys.firstWhere((k) => target.contains(k), orElse: () => '');
    if (key.isEmpty) {
      return 'I do not have an opening shortcut for $target yet. Try Chrome, Camera, Settings, Calculator, Maps, YouTube, WhatsApp, or Instagram.';
    }
    try {
      await launchUrl(Uri.parse(sites[key]!), mode: LaunchMode.externalApplication);
      return 'Opening $key.';
    } catch (_) {
      return 'I could not open $key on this phone.';
    }
  }

  Future<String> _askAI(String message) async {
    try {
      final response = await http.post(Uri.parse(aiEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'history': _messages.length <= 1 ? <Map<String, String>>[] :
            _messages.sublist(0, _messages.length - 1)
              .skip(_messages.length > 11 ? _messages.length - 11 : 0)
              .map((line) => <String, String>{
                'role': line.isUser ? 'user' : 'assistant',
                'content': line.text,
              }).toList(),
        }),
      ).timeout(const Duration(seconds: 18));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final reply = data['reply'] ?? data['response'] ?? data['message'];
        if (reply is String && reply.trim().isNotEmpty) return reply.trim();
      }
    } catch (_) {}
    return 'I can handle basic commands, but my AI brain is not connected right now. Deploy the Veylola backend and configure its AI provider to answer general questions.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.graphic_eq, color: Color(0xFF69D9FF)), SizedBox(width: 9),
          Text('VEYLOLA VOICE', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            tooltip: _wakeMode ? 'Pause wake word' : 'Enable wake word',
            onPressed: _toggleWake,
            icon: Icon(_wakeMode ? Icons.hearing : Icons.hearing_disabled,
              color: _wakeMode ? const Color(0xFF69D9FF) : null),
          ),
        ],
      ),
      body: SafeArea(child: Column(children: [
        const SizedBox(height: 10),
        Container(
          width: 142, height: 142,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFF164C72), Color(0xFF091321), Color(0xFF070B14)]),
            border: Border.all(color: const Color(0xFF69D9FF).withValues(alpha: 0.7), width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFF32C8FF).withValues(alpha: _listening ? 0.35 : 0.12), blurRadius: 32, spreadRadius: 5)],
          ),
          child: Icon(_listening ? Icons.mic : Icons.memory, size: 64, color: const Color(0xFF8DE5FF)),
        ),
        const SizedBox(height: 10),
        Text(_status, style: const TextStyle(color: Color(0xFF69D9FF), letterSpacing: 3, fontSize: 12)),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text('Voice commands • Smart actions • AI assistant',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13))),
        const SizedBox(height: 10),
        Expanded(child: ListView.builder(
          controller: _scroll, padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          itemCount: _messages.length,
          itemBuilder: (context, i) {
            final item = _messages[i];
            return Align(
              alignment: item.isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 330),
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: item.isUser ? const Color(0xFF123B54) : const Color(0xFF121A29),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF69D9FF).withValues(alpha: 0.16)),
                ),
                child: Text(item.text, style: const TextStyle(fontSize: 14, height: 1.4)),
              ),
            );
          },
        )),
        if (_wakeMode)
          const Padding(padding: EdgeInsets.only(bottom: 5), child: Text('Background wake-word mode is enabled', style: TextStyle(color: Color(0xFF69D9FF), fontSize: 11))),
        Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 12), child: Row(children: [
          Expanded(child: TextField(
            controller: _input,
            textInputAction: TextInputAction.send,
            onSubmitted: _handle,
            decoration: InputDecoration(
              hintText: 'Ask Veylola anything…',
              filled: true, fillColor: const Color(0xFF121A29),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          )),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _busy ? null : () => _handle(_input.text),
            icon: const Icon(Icons.arrow_upward),
          ),
          const SizedBox(width: 4),
          FloatingActionButton.small(
            heroTag: 'mic',
            onPressed: _listen,
            backgroundColor: _listening ? const Color(0xFFFF6B6B) : const Color(0xFF69D9FF),
            foregroundColor: const Color(0xFF07111C),
            child: Icon(_listening ? Icons.stop : Icons.mic),
          ),
        ])),
      ])),
    );
  }
}
