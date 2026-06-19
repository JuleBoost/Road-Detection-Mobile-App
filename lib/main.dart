import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: DetectorScreen()));
}

class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key});
  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen> {
  static const platform = MethodChannel('com.example.test2/detector');
  CameraController? _controller;
  List<dynamic> _recognitions = [];
  bool _isDetecting = false;
  String _inferenceTime = "0";
  String? _modelPath;
  List<Map<String, dynamic>> _history = [];
  bool _isFirestoreEnabled = false; // Stub for toggle

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.storage].request();
  }

  Future<void> _pickModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      final path = result.files.single.path;
      final bool success = await platform.invokeMethod('loadModel', {"path": path});
      if (success) {
        setState(() => _modelPath = path);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Model Loaded Successfully")));
      }
    }
  }

  void _toggleCamera() async {
    if (_controller != null) {
      await _controller!.dispose();
      setState(() {
        _controller = null;
        _recognitions = [];
      });
      return;
    }

    final cameras = await availableCameras();
    // Using bgra8888 for easier processing in Swift
    _controller = CameraController(cameras[0], ResolutionPreset.medium, imageFormatGroup: ImageFormatGroup.bgra8888, enableAudio: false);
    
    await _controller!.initialize();
    _controller!.startImageStream((image) async {
      if (_isDetecting || _modelPath == null) return;
      _isDetecting = true;

      final stopwatch = Stopwatch()..start();
      try {
        final List<dynamic> results = await platform.invokeMethod('detect', {
          "buffer": image.planes[0].bytes,
          "width": image.width,
          "height": image.height,
        });
        
        stopwatch.stop();
        setState(() {
          _recognitions = results;
          _inferenceTime = "${stopwatch.elapsedMilliseconds}ms";
          for (var res in results) {
            _history.add({
              'label': res['label'],
              'confidence': res['confidence'],
              'timestamp': DateTime.now().toIso8601String()
            });
          }
        });
      } finally {
        _isDetecting = false;
      }
    });
    setState(() {});
  }

  Future<void> _saveData() async {
    if (_history.isEmpty) return;
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/detections.json');
    String content = jsonEncode(_history);
    await file.writeAsString(content);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved to: ${file.path}")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("CoreML Detector"), actions: [
        Switch(value: _isFirestoreEnabled, onChanged: (v) => setState(() => _isFirestoreEnabled = v))
      ]),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_controller != null && _controller!.value.isInitialized)
                  CameraPreview(_controller!),
                CustomPaint(painter: DetectionPainter(_recognitions), child: Container()),
                Positioned(
                  top: 10, left: 10,
                  child: Text("Inference: $_inferenceTime", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              children: [
                ElevatedButton(onPressed: _pickModel, child: const Text("Load Model")),
                ElevatedButton(onPressed: _toggleCamera, child: Text(_controller == null ? "Start Camera" : "Stop Camera")),
                ElevatedButton(onPressed: _saveData, child: const Text("Save Detections")),
                ElevatedButton(onPressed: () => setState(() => _history.clear()), child: const Text("Clear Data")),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class DetectionPainter extends CustomPainter {
  final List<dynamic> results;
  DetectionPainter(this.results);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0..color = Colors.red;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var res in results) {
      final rect = Rect.fromLTWH(
        res['x'] * size.width,
        res['y'] * size.height,
        res['w'] * size.width,
        res['h'] * size.height,
      );
      canvas.drawRect(rect, paint);
      
      textPainter.text = TextSpan(
        text: "${res['label']} ${(res['confidence'] * 100).toStringAsFixed(0)}%",
        style: const TextStyle(color: Colors.red, backgroundColor: Colors.black54),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
