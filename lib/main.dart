import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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

class _AssistantPageState extends State<AssistantPage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const MethodChannel _backgroundChannel = MethodChannel('com.veylola.veylola_voice/background');
  Future<void> _openAccessibilitySettings() async {
    try {
      await _backgroundChannel.invokeMethod('accessibilitySettings');
      if (mounted) _add('Android Accessibility settings opened. Select Veylola Voice and turn it on only if you want to grant this service access. Android requires you to enable it yourself.', false);
    } catch (_) {
      if (mounted) _add('Open Android Settings > Accessibility > Downloaded apps/Installed services > Veylola Voice, then enable it yourself if you choose.', false);
    }
  }

  Future<void> _openBatteryProtectionSettings() async {
    try {
      await _backgroundChannel.invokeMethod('batterySettings');
      if (mounted) _add('Android will ask whether Veylola may ignore battery optimization. Approve only if you want background listening; this still cannot override every system restriction.', false);
    } catch (_) {
      try { await _backgroundChannel.invokeMethod('appSettings'); }
      catch (_) { if (mounted) _add('Open Android Settings > Apps > Veylola Voice > Battery and choose Unrestricted if your phone offers it.', false); }
    }
  }

  Future<void> _setBackgroundListening(bool enabled) async {
    try { await _backgroundChannel.invokeMethod(enabled ? 'start' : 'stop'); }
    catch (_) { if (mounted) _add('Background listening service could not start. Check microphone permission and rebuild the APK.', false); }
  }
  late final AnimationController _liquidController;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _tts = FlutterTts();
  final _speech = stt.SpeechToText();
  final List<ChatLine> _messages = [
    ChatLine('Veylola online. Tap the microphone and say “Hey Veylola”, or type a command.', false),
  ];
  bool _ready = false, _listening = false, _busy = false, _wakeMode = false;
  String _status = 'READY';
  // Production Render endpoint. The app connects automatically; no manual Settings entry is needed.
  static const String apiBaseUrl = 'https://seri-muob.onrender.com';
  static const String aiEndpoint = '$apiBaseUrl/api/chat';
  bool _serverReachable = false;
  bool _onlineAIConfigured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liquidController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
    _initVoice();
    _checkServer();
    _tts.setSpeechRate(0.47);
    _tts.setPitch(0.92);
  }

  Future<void> _checkServer() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/health'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _serverReachable = true;
          _onlineAIConfigured = data is Map && data['online_ai_configured'] == true;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() { _serverReachable = false; _onlineAIConfigured = false; });
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
    _liquidController.dispose();
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
    await _checkServer();
    return _serverReachable
        ? 'Seri reached the Render server, but the chat request failed. Check the server logs and AI provider settings on Render.'
        : 'Seri could not reach its Render server. Check your internet connection or open https://seri-muob.onrender.com/health to test the server.';
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF63D9FF);
    const electricBlue = Color(0xFF286BFF);
    const midnight = Color(0xFF030712);
    return Scaffold(
      backgroundColor: midnight,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: midnight.withValues(alpha: 0.48),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.graphic_eq_rounded, color: cyan, size: 25),
          SizedBox(width: 9),
          Text('VEYLOLA', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w800, fontSize: 17)),
          SizedBox(width: 7),
          Text('VOICE', style: TextStyle(letterSpacing: 2, color: cyan, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Allow background listening',
            onPressed: _openBatteryProtectionSettings,
            icon: const Icon(Icons.battery_charging_full_rounded, color: cyan),
          ),
          IconButton(
            tooltip: 'Accessibility settings',
            onPressed: _openAccessibilitySettings,
            icon: const Icon(Icons.accessibility_new_rounded, color: cyan),
          ),
          IconButton(
            tooltip: _wakeMode ? 'Pause wake word' : 'Enable wake word',
            onPressed: _toggleWake,
            icon: Icon(_wakeMode ? Icons.hearing_rounded : Icons.hearing_disabled_rounded,
              color: _wakeMode ? cyan : Colors.white70),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF08172D), midnight, Color(0xFF03050D)],
            stops: [0, 0.48, 1],
          ),
        ))),
        Positioned(top: 80, left: -85, child: _GlowBlob(color: electricBlue.withValues(alpha: 0.18), size: 220)),
        Positioned(top: 310, right: -105, child: _GlowBlob(color: cyan.withValues(alpha: 0.12), size: 250)),
        SafeArea(child: Column(children: [
          const SizedBox(height: 64),
          AnimatedBuilder(
            animation: _liquidController,
            builder: (context, child) {
              final t = _liquidController.value;
              return Container(
                width: 174 + (t * 8), height: 174 + (t * 8),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [cyan.withValues(alpha: 0.72), electricBlue.withValues(alpha: 0.65), Colors.white.withValues(alpha: 0.12)],
                  ),
                  boxShadow: [
                    BoxShadow(color: cyan.withValues(alpha: (_listening ? 0.36 : 0.16) + t * 0.08), blurRadius: 34 + t * 12, spreadRadius: 1 + t * 3),
                    BoxShadow(color: electricBlue.withValues(alpha: 0.2), blurRadius: 48, spreadRadius: 6),
                  ],
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: Alignment(-0.35 - t * 0.12, -0.55),
                          radius: 1.15,
                          colors: [Colors.white.withValues(alpha: 0.25), cyan.withValues(alpha: 0.16), Color(0xFF061326).withValues(alpha: 0.94)],
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.42), width: 1.2),
                      ),
                      child: Stack(alignment: Alignment.center, children: [
                        Positioned(top: 17 + t * 7, left: 32 + t * 10,
                          child: Container(width: 52, height: 20,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(30))),
                        ),
                        Icon(_listening ? Icons.graphic_eq_rounded : Icons.memory_rounded, size: 66,
                          color: _listening ? Colors.white : const Color(0xFF9BEAFF)),
                        Positioned(bottom: 19, child: Container(width: 34, height: 3,
                          decoration: BoxDecoration(color: cyan.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)))),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(_status, style: const TextStyle(color: cyan, letterSpacing: 4, fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text('YOUR VOICE. YOUR ASSISTANT.', style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 10, letterSpacing: 2.0)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: _StatusPill(icon: Icons.auto_awesome_rounded, label: _onlineAIConfigured ? 'AI CONNECTED' : (_serverReachable ? 'SERVER ONLINE' : 'CONNECTING'), active: _onlineAIConfigured || _serverReachable)),
              const SizedBox(width: 8),
              Expanded(child: _StatusPill(icon: Icons.mic_none_rounded, label: _wakeMode ? 'WAKE ON' : 'VOICE READY', active: _wakeMode || _ready)),
              const SizedBox(width: 8),
              Expanded(child: _StatusPill(icon: Icons.bolt_rounded, label: _busy ? 'THINKING' : 'ONLINE', active: !_busy)),
            ]),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: cyan.withValues(alpha: 0.16)),
                    ),
                    child: _messages.isEmpty
                      ? Center(child: Text('Your conversation starts here', style: TextStyle(color: Colors.white.withValues(alpha: 0.45))))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final item = _messages[i];
                            return Align(
                              alignment: item.isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 310),
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: item.isUser
                                    ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xCC1266A6), Color(0xAA143B79)])
                                    : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                                        colors: [Colors.white.withValues(alpha: 0.105), Colors.white.withValues(alpha: 0.035)]),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(item.isUser ? 18 : 5),
                                    bottomRight: Radius.circular(item.isUser ? 5 : 18),
                                  ),
                                  border: Border.all(color: (item.isUser ? cyan : Colors.white).withValues(alpha: 0.19)),
                                  boxShadow: item.isUser ? [BoxShadow(color: electricBlue.withValues(alpha: 0.09), blurRadius: 15)] : null,
                                ),
                                child: Text(item.text, style: const TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFFF2F8FF))),
                              ),
                            );
                          },
                        ),
                  ),
                ),
              ),
            ),
          ),
          if (_wakeMode)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('◉  BACKGROUND WAKE WORD ENABLED', style: TextStyle(color: cyan.withValues(alpha: 0.9), fontSize: 9, letterSpacing: 1.2)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.075),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: cyan.withValues(alpha: 0.25)),
                    boxShadow: [BoxShadow(color: electricBlue.withValues(alpha: 0.09), blurRadius: 20)],
                  ),
                  child: Row(children: [
                    const SizedBox(width: 8),
                    Expanded(child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handle,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Message Veylola…',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.43)),
                        filled: false, border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                      ),
                    )),
                    IconButton(
                      onPressed: _busy ? null : () => _handle(_input.text),
                      icon: const Icon(Icons.arrow_upward_rounded, color: cyan),
                      style: IconButton.styleFrom(backgroundColor: cyan.withValues(alpha: 0.12)),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: _listening ? [const Color(0xFFFF7190), const Color(0xFFD72D61)] : [cyan, electricBlue]),
                        boxShadow: [BoxShadow(color: (_listening ? const Color(0xFFFF7190) : cyan).withValues(alpha: 0.3), blurRadius: 16)],
                      ),
                      child: IconButton(
                        onPressed: _listen,
                        color: midnight,
                        icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ]),
                ),
              ),
            ),
          ),
        ])),
      ]),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, required this.active});
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF63D9FF) : Colors.white54;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 8.5, letterSpacing: 0.7, color: color, fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }
}
