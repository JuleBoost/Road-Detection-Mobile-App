import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MaterialApp(home: NativeDetectorScreen()));

class NativeDetectorScreen extends StatefulWidget {
  const NativeDetectorScreen({super.key});
  @override
  State<NativeDetectorScreen> createState() => _NativeDetectorScreenState();
}

class _NativeDetectorScreenState extends State<NativeDetectorScreen> {
  static const platform = MethodChannel('com.example.test2/detector');
  String _status = "Ready";
  String _inferenceTime = "0ms";
  bool _isCameraRunning = false;
  final List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    // Listen for data from Swift
    platform.setMethodCallHandler((call) async {
      if (call.method == "updateResults") {
        setState(() {
          _inferenceTime = "${call.arguments['time']}ms";
          final List results = call.arguments['results'];
          for (var res in results) {
            _history.add({'label': res, 'time': DateTime.now().toIso8601String()});
          }
        });
      }
    });
  }

  Future<void> _pickModel() async {
    setState(() => _status = "Picking model...");
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      final success = await platform.invokeMethod('loadModel', {"path": result.files.single.path});
      setState(() => _status = success ? "Model Loaded" : "Load Failed");
    }
  }

  void _toggleCamera() {
    setState(() {
      _isCameraRunning = !_isCameraRunning;
      _status = _isCameraRunning ? "Detecting..." : "Camera Stopped";
    });
  }

  Future<void> _saveData() async {
    setState(() => _status = "Saving...");
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/detections.json');
    await file.writeAsString(jsonEncode(_history));
    setState(() => _status = "Saved: ${_history.length} items");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // The Native Camera View
          if (_isCameraRunning)
            const SizedBox.expand(
              child: UiKitView(
                viewType: 'native-cam-view',
                creationParams: {},
                creationParamsCodec: StandardMessageCodec(),
              ),
            ),
          
          // UI Overlay
          SafeArea(
            child: Column(
              children: [
                Container(
                  color: Colors.black54,
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    "Status: $_status | Inference: $_inferenceTime",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      ElevatedButton(onPressed: _pickModel, child: const Text("Load Model")),
                      ElevatedButton(
                        onPressed: _toggleCamera, 
                        style: ElevatedButton.styleFrom(backgroundColor: _isCameraRunning ? Colors.red : Colors.blue),
                        child: Text(_isCameraRunning ? "Stop Camera" : "Start Camera"),
                      ),
                      ElevatedButton(onPressed: _saveData, child: const Text("Save JSON")),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
