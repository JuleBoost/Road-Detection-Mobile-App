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
    try { await _player.play(AssetSource('loading.mp3')); } catch (e) { print(e); }
    await Future.delayed(const Duration(seconds: 4));
    await Geolocator.requestPermission();
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
        Text("SECURE SYSTEM INITIALIZING...", style: TextStyle(color: Colors.white, letterSpacing: 1.5, fontSize: 12)),
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
  String _status = "Ready";
  String _infTime = "0ms";
  String _lastSyncMsg = "";
  bool _isCam = false;
  bool _autoSync = false;
  final List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    platform.setMethodCallHandler((call) async {
      if (call.method == "updateResults") {
        setState(() => _infTime = "${call.arguments['time']}ms");
        if (_autoSync) {
          final List res = call.arguments['results'];
          if (res.isNotEmpty) _syncToSupabase(res.first.toString());
        }
      }
    });
  }

  Future<void> _syncToSupabase(String label) async {
    try {
      Position p = await Geolocator.getCurrentPosition();
      List<Placemark> pm = await placemarkFromCoordinates(p.latitude, p.longitude);
      Placemark place = pm.first;
      final now = DateTime.now().toIso8601String();
      
      final data = {
        'anomaly': label,
        'category': 'Real-time Detection',
        'severity': 'Medium',
        'status': 'detected',
        'confidence': 0.98,
        'lat': p.latitude, // GPS Coordinate
        'lng': p.longitude, // GPS Coordinate
        'address': "${place.street}, ${place.locality}, ${place.country}",
        'municipality_id': place.postalCode ?? "N/A",
        'municipality_name': place.locality ?? "N/A",
        'district': place.subLocality ?? "N/A",
        'governorate': place.administrativeArea ?? "N/A",
        'reports_count': 1,
        'first_seen_at': now,
        'last_seen_at': now,
        'timestamp': now,
        'updated_at': now,
      };
      
      await supabase.from('anomalies').insert(data);
      
      setState(() {
        _history.add(data);
        _lastSyncMsg = "SUCCESS: Logged to Database";
      });
      
      // Clear message after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _lastSyncMsg = "");
      });
    } catch (e) {
      print("Sync Error: $e");
    }
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(build: (pw.Context context) => [
      pw.Header(level: 0, text: "ANOMALY DETECTION REPORT"),
      pw.TableHelper.fromTextArray(data: <List<String>>[
        ['Anomaly', 'District', 'Governorate', 'Lat/Lng', 'Time'],
        ..._history.map((e) => [e['anomaly'], e['district'] ?? '', e['governorate'] ?? '', "${e['lat']},${e['lng']}", e['timestamp'].toString().substring(0, 16)])
      ]),
    ]));
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/report.pdf");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Exported Detection Data');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_isCam) const SizedBox.expand(child: UiKitView(viewType: 'native-cam-view', creationParams: {}, creationParamsCodec: StandardMessageCodec())),
        SafeArea(child: Column(children: [
          Container(
            color: Colors.black87, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("STATUS: $_status | $_infTime", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                Row(children: [
                  const Text("AUTO-DB", style: TextStyle(color: Colors.white, fontSize: 10)),
                  Switch(value: _autoSync, activeColor: Colors.blueAccent, onChanged: (v) => setState(() => _autoSync = v)),
                ])
              ]),
              if (_lastSyncMsg.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(_lastSyncMsg, style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(25), color: Colors.black54,
            child: Wrap(spacing: 15, alignment: WrapAlignment.center, children: [
              ElevatedButton.icon(icon: const Icon(Icons.file_upload), onPressed: () async {
                FilePickerResult? r = await FilePicker.platform.pickFiles();
                if (r != null) { await platform.invokeMethod('loadModel', {"path": r.files.single.path}); setState(() => _status = "Model Online"); }
              }, label: const Text("Load Model")),
              ElevatedButton.icon(icon: Icon(_isCam ? Icons.stop : Icons.videocam), style: ElevatedButton.styleFrom(backgroundColor: _isCam ? Colors.red : Colors.blueAccent), onPressed: () => setState(() => _isCam = !_isCam), label: Text(_isCam ? "Stop" : "Start")),
              ElevatedButton.icon(icon: const Icon(Icons.share), onPressed: _generatePdf, label: const Text("Share PDF")),
            ]),
          )
        ])),
      ]),
    );
  }
}
