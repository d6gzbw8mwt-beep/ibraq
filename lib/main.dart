// الإبراق الإلكتروني — تطبيق Flutter
// الواجهة الكاملة (المهام، المحادثات، المرفوعات، التوقيع…) موجودة في assets/web
// وهذا الملف يضيف قدرات الهاتف الأصلية:
//   • تتبّع الموقع بالخلفية أثناء الدوام (خدمة أمامية بإشعار ثابت)
//   • التحقق بالبصمة / بصمة الوجه / رمز القفل قبل التوقيع
//   • إشعارات النظام
//   • فتح الملفات (PDF / Excel / صور) بتطبيقات الهاتف
//   • المايكروفون للرسائل الصوتية والكاميرا للمرفقات

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

const int kPort = 8317;
final InAppLocalhostServer localServer =
    InAppLocalhostServer(documentRoot: 'assets/web', port: kPort);
final FlutterLocalNotificationsPlugin notifs = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0C5A32),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await localServer.start();
  await notifs.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  ));
  runApp(const IbraqApp());
}

class IbraqApp extends StatelessWidget {
  const IbraqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'الإبراق الإلكتروني',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0C5A32), useMaterial3: true),
      home: const PermissionGate(),
    );
  }
}

// ---------------- بوابة الأذونات: لا يعمل التطبيق إلا بعد الموافقة على كل الأذونات ----------------
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});
  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> with WidgetsBindingObserver {
  bool _ok = false;
  bool _busy = false;
  bool _waitingSettings = false;

  static const _labels = {
    'location': 'الموقع (السماح طوال الوقت)',
    'notification': 'الإشعارات',
    'microphone': 'المايكروفون',
    'camera': 'الكاميرا',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingSettings && !_ok) {
      _waitingSettings = false;
      _run();
    }
  }

  Future<List<String>> _missing() async {
    final m = <String>[];
    if (!await Permission.locationWhenInUse.isGranted || !await Permission.locationAlways.isGranted) m.add('location');
    if (!await Permission.notification.isGranted) m.add('notification');
    if (!await Permission.microphone.isGranted) m.add('microphone');
    if (!await Permission.camera.isGranted) m.add('camera');
    return m;
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await [Permission.notification, Permission.microphone, Permission.camera, Permission.locationWhenInUse].request();
      if (await Permission.locationWhenInUse.isGranted && !await Permission.locationAlways.isGranted) {
        await Permission.locationAlways.request();
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }
      final miss = await _missing();
      if (!mounted) return;
      if (miss.isEmpty) {
        setState(() => _ok = true);
        return;
      }
      await _denied(miss);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _denied(List<String> miss) async {
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('يجب الموافقة على الأذونات'),
          content: Text('لا يعمل تطبيق الإبراق إلا بعد الموافقة على كل الأذونات التالية:\n\n'
              '${miss.map((k) => '• ${_labels[k]}').join('\n')}\n\n'
              'اضغط «تفعيل الأذونات» ثم وافق عليها، أو سيتم إغلاق التطبيق.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إغلاق التطبيق')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تفعيل الأذونات')),
          ],
        ),
      ),
    );
    if (again != true) {
      await SystemNavigator.pop();
      exit(0);
    }
    // إذا رفض المستخدم نهائياً، النظام لا يعرض الطلب مرة أخرى: نفتح إعدادات التطبيق
    bool permanent = false;
    for (final p in [Permission.notification, Permission.microphone, Permission.camera, Permission.locationWhenInUse, Permission.locationAlways]) {
      if (await p.isPermanentlyDenied) permanent = true;
    }
    final onlyAlways = miss.length == 1 && miss.first == 'location' && await Permission.locationWhenInUse.isGranted;
    if (permanent || onlyAlways) {
      _waitingSettings = true;
      await openAppSettings();
      return;
    }
    _busy = false;
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    if (_ok) return const WebShell();
    return Scaffold(
      backgroundColor: const Color(0xFF0C5A32),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 110,
              height: 110,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Image.asset('assets/web/logo-mark.png'),
            ),
            const SizedBox(height: 22),
            const Text('الإبراق الإلكتروني',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('للمتابعة وافق على أذونات الموقع والإشعارات والمايكروفون والكاميرا',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 24),
            _busy
                ? const CircularProgressIndicator(color: Colors.white)
                : FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0C5A32)),
                    onPressed: _run,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      child: Text('تفعيل الأذونات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
          ]),
        ),
      ),
    );
  }
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  InAppWebViewController? _web;
  StreamSubscription<Position>? _posSub;
  final LocalAuthentication _auth = LocalAuthentication();
  int _notifId = 1;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _askBasicPermissions();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _askBasicPermissions() async {}

  // ---------------- الموقع بالخلفية ----------------
  Future<bool> _startTracking(Map<String, dynamic> args) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return false;
    }
    if (perm == LocationPermission.whileInUse) {
      // السماح «طوال الوقت» حتى يستمر التتبع والهاتف مقفول
      await Permission.locationAlways.request();
    }
    await _posSub?.cancel();
    final String title = (args['title'] ?? 'الإبراق الإلكتروني').toString();
    final String text = (args['text'] ?? 'مشاركة الموقع أثناء الدوام').toString();
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            intervalDuration: const Duration(seconds: 30),
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: title,
              notificationText: text,
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
            pauseLocationUpdatesAutomatically: false,
          );
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      _web?.evaluateJavascript(
          source:
              'window.__nativePos && window.__nativePos(${p.latitude}, ${p.longitude}, ${p.accuracy});');
    }, onError: (_) {});
    return true;
  }

  Future<bool> _stopTracking() async {
    await _posSub?.cancel();
    _posSub = null;
    return true;
  }

  // ---------------- البصمة / الوجه / الرمز ----------------
  Future<dynamic> _bioAuth(String reason) async {
    try {
      if (!await _auth.isDeviceSupported()) return 'unavailable';
      final bool ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      return ok;
    } catch (_) {
      return 'unavailable';
    }
  }

  // ---------------- الإشعارات ----------------
  Future<bool> _notify(String title, String body) async {
    await notifs.show(
      _notifId++,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ibraq_main',
          'تنبيهات الإبراق',
          channelDescription: 'المهام العاجلة والتوجيهات والرسائل',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    return true;
  }

  // ---------------- فتح الملفات ----------------
  Future<bool> _openFile(String name, String b64) async {
    final String safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final Directory dir = await getTemporaryDirectory();
    final File f = File('${dir.path}/$safe');
    await f.writeAsBytes(base64Decode(b64));
    final OpenResult r = await OpenFilex.open(f.path);
    return r.type == ResultType.done;
  }

  void _registerHandlers(InAppWebViewController c) {
    c.addJavaScriptHandler(
        handlerName: 'startTracking',
        callback: (args) async => _startTracking(
            args.isNotEmpty && args[0] is Map ? Map<String, dynamic>.from(args[0] as Map) : {}));
    c.addJavaScriptHandler(handlerName: 'stopTracking', callback: (args) async => _stopTracking());
    c.addJavaScriptHandler(
        handlerName: 'bioAuth',
        callback: (args) async => _bioAuth(args.isNotEmpty ? '${args[0]}' : 'تأكيد الهوية'));
    c.addJavaScriptHandler(
        handlerName: 'notify',
        callback: (args) async =>
            _notify(args.isNotEmpty ? '${args[0]}' : 'الإبراق', args.length > 1 ? '${args[1]}' : ''));
    c.addJavaScriptHandler(
        handlerName: 'openFile',
        callback: (args) async => args.length >= 3 ? _openFile('${args[0]}', '${args[2]}') : false);
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _handleBack() async {
    final c = _web;
    if (c == null) return;
    final handled = await c.evaluateJavascript(source: 'window.__nativeBack ? window.__nativeBack() : false');
    if (handled != true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0C5A32),
        body: SafeArea(
          bottom: false,
          child: Stack(children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri('http://localhost:$kPort/index.html')),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
                javaScriptCanOpenWindowsAutomatically: true,
                supportZoom: false,
                geolocationEnabled: true,
                allowFileAccess: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                transparentBackground: false,
                hardwareAcceleration: true,
                useHybridComposition: true,
                overScrollMode: OverScrollMode.NEVER,
                textZoom: 100,
                minimumFontSize: 1,
                verticalScrollBarEnabled: false,
                horizontalScrollBarEnabled: false,
                disableHorizontalScroll: true,
                disableContextMenu: false,
                builtInZoomControls: false,
                displayZoomControls: false,
                useWideViewPort: true,
                loadWithOverviewMode: false,
                cacheEnabled: true,
              ),
              onWebViewCreated: (c) {
                _web = c;
                _registerHandlers(c);
              },
              onLoadStop: (c, url) {
                if (_loading) setState(() => _loading = false);
              },
              onPermissionRequest: (c, req) async {
                if (req.resources.contains(PermissionResourceType.MICROPHONE)) {
                  await Permission.microphone.request();
                }
                if (req.resources.contains(PermissionResourceType.CAMERA)) {
                  await Permission.camera.request();
                }
                return PermissionResponse(resources: req.resources, action: PermissionResponseAction.GRANT);
              },
              onGeolocationPermissionsShowPrompt: (c, origin) async =>
                  GeolocationPermissionShowPromptResponse(origin: origin, allow: true, retain: true),
              shouldOverrideUrlLoading: (c, nav) async {
                final uri = nav.request.url;
                if (uri != null && uri.host != 'localhost' && uri.host != '127.0.0.1') {
                  await _openExternal(uri);
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (c, action) async {
                final uri = action.request.url;
                if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                  await _openExternal(uri);
                }
                return false;
              },
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}
