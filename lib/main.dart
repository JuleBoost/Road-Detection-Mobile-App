import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://afhlqhzcnbqbvwgkttfz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmaGxxaHpjbmJxYnZ3Z2t0dGZ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxMDcwNjAsImV4cCI6MjA5NzY4MzA2MH0.-OYWckYZipMQE6F8R5FBEPmBCtWDiCCeM_lVtG4AK6Y',
  );
  runApp(const MaterialApp(home: SplashScreen()));
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  Future<void> _startLoading() async {
    try { await _player.play(AssetSource('loading.mp3')); } catch (e) {}
    
    // Request Location Permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DetectorScreen()));
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.radar, size: 100, color: Colors.blueAccent),
        SizedBox(height: 25),
        CircularProgressIndicator(color: Colors.blueAccent),
        SizedBox(height: 15),
        Text("SYSTEM INITIALIZING...", style: TextStyle(color: Colors.white, letterSpacing: 1.5, fontSize: 12)),
      ])),
    );
  }
}

class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key});
  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen> {
  static const platform = MethodChannel('com.example.test2/detector');
  final supabase = Supabase.instance.client;
  String _infTime = "0ms";
  String _lastSyncMsg = "";
  bool _isCam = false;
  bool _autoSync = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  final List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler((call) async {
      if (call.method == "updateResults") {
        if (!mounted) return;
        setState(() => _infTime = "${call.arguments['time']}ms");
        
        if (_autoSync && !_isSyncing) {
          final List res = call.arguments['results'];
          if (res.isNotEmpty) {
            // Throttle: Sync only once every 4 seconds
            if (_lastSyncTime == null || DateTime.now().difference(_lastSyncTime!).inSeconds > 4) {
              _syncToSupabase(res.first.toString());
            }
          }
        }
      }
    });
  }

  Future<void> _syncToSupabase(String label) async {
    _isSyncing = true;
    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> pm = await placemarkFromCoordinates(p.latitude, p.longitude);
      Placemark place = pm.first;
      final now = DateTime.now().toIso8601String();
      
      final data = {
        'anomaly': label,
        'category': 'Detection',
        'severity': 'Medium',
        'status': 'detected',
        'confidence': 0.95,
        'lat': p.latitude,
        'lng': p.longitude,
        'address': "${place.street}, ${place.locality}",
        'municipality_id': place.postalCode ?? "0000",
        'municipality_name': place.locality ?? "Unknown",
        'district': place.subLocality ?? "Unknown",
        'governorate': place.administrativeArea ?? "Unknown",
        'reports_count': 1,
        'first_seen_at': now,
        'last_seen_at': now,
        'timestamp': now,
        'updated_at': now,
      };
      
      await supabase.from('anomalies').insert(data);
      
      setState(() {
        _history.add(data);
        _lastSyncTime = DateTime.now();
        _lastSyncMsg = "SYNC SUCCESS: $label";
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _lastSyncMsg = "");
      });
    } catch (e) {
      print("Sync Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _generatePdf() async {
    if (_history.isEmpty) return;
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(build: (pw.Context context) => [
      pw.Header(level: 0, text: "DETECTION LOG REPORT"),
      pw.TableHelper.fromTextArray(
        headers: ['Anomaly', 'District', 'Gov', 'Time'],
        data: _history.map((e) => [
          e['anomaly'].toString(),
          e['district'].toString(),
          e['governorate'].toString(),
          e['timestamp'].toString().substring(11, 19)
        ]).toList(),
      ),
    ]));

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/report.pdf");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Report');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_isCam) const SizedBox.expand(child: UiKitView(viewType: 'native-cam-view', creationParams: {}, creationParamsCodec: StandardMessageCodec())),
        
        // CENTER NOTIFICATION
        if (_lastSyncMsg.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.8), borderRadius: BorderRadius.circular(10)),
              child: Text(_lastSyncMsg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),

        SafeArea(child: Column(children: [
          Container(
            color: Colors.black87, padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("INF: $_infTime", style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
              Row(children: [
                const Text("AUTO-DB", style: TextStyle(color: Colors.white, fontSize: 10)),
                Switch(value: _autoSync, activeColor: Colors.blueAccent, onChanged: (v) => setState(() => _autoSync = v)),
              ])
            ]),
          ),
          const Spacer(),
          Padding(padding: const EdgeInsets.all(20), child: Wrap(spacing: 10, children: [
            ElevatedButton(onPressed: () async {
              FilePickerResult? r = await FilePicker.platform.pickFiles();
              if (r != null) await platform.invokeMethod('loadModel', {"path": r.files.single.path});
            }, child: const Text("Load Model")),
            ElevatedButton(onPressed: () => setState(() => _isCam = !_isCam), child: Text(_isCam ? "Stop" : "Start")),
            ElevatedButton(onPressed: _generatePdf, child: const Text("Share PDF")),
          ]))
        ])),
      ]),
    );
  }
}
