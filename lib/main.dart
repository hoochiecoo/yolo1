import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:image/image.dart' as img;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: CameraScreen(cameras: cameras),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isDetecting = false;
  bool _lineDetected = false;
  int _lineLength = 0;
  String _status = "Initializing YOLO...";
  late UltralyticsYolo yolo;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initYolo();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller.initialize();
    if (!mounted) return;

    _controller.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;
      try {
        final pngBytes = await _convertYUVToPng(image);
        final results = await yolo.detectOnImage(pngBytes);

        bool detected = results.isNotEmpty;
        int maxLen = 0;
        for (var r in results) {
          int w = r['x2'] - r['x1'];
          if (w > maxLen) maxLen = w;
        }

        setState(() {
          _lineDetected = detected;
          _lineLength = maxLen;
          _status = detected ? "Object Detected!" : "Scanning...";
        });
      } catch (e) {
        setState(() => _status = "Error: $e");
      } finally {
        _isDetecting = false;
      }
    });

    setState(() {});
  }

  Future<void> _initYolo() async {
    yolo = await UltralyticsYolo.create();
    setState(() => _status = "YOLO Ready");
  }

  Future<Uint8List> _convertYUVToPng(CameraImage image) async {
    final width = image.width;
    final height = image.height;
    final imgData = img.Image(width, height);
    final plane = image.planes[0]; 
    final buffer = plane.bytes;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixelIndex = y * plane.bytesPerRow + x;
        final luminance = buffer[pixelIndex];
        imgData.setPixelRgba(x, y, luminance, luminance, luminance);
      }
    }
    return Uint8List.fromList(img.encodePng(imgData));
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("YOLO Camera Detector")),
      body: Stack(
        children: [
          CameraPreview(_controller),
          if (_lineDetected)
            Center(
              child: Container(
                height: 4,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.red.withOpacity(0.8),
                        blurRadius: 10,
                        spreadRadius: 2)
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _lineDetected
                    ? Colors.red.withOpacity(0.8)
                    : Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _status,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  if (_lineDetected)
                    Text(
                      "Width: $_lineLength px",
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
