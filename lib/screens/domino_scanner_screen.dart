import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/dot_detector.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class DominoScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DominoScannerScreen({super.key, required this.cameras});

  @override
  State<DominoScannerScreen> createState() => _DominoScannerScreenState();
}

class _DominoScannerScreenState extends State<DominoScannerScreen> {
  late CameraController _cameraController;
  final DotDetector _detector = DotDetector();

  bool _isProcessing = false;
  bool _cameraReady = false;
  Uint8List? _processedFrame;
  int _dotCount = 0;
  int _maxDots = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _pickAndProcessImage() async {
    // Pause the camera stream while processing a still image
    await _cameraController.stopImageStream();

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) {
        // User cancelled — resume camera
        await _cameraController.startImageStream(_onFrameAvailable);
        return;
      }

      final bytes = await pickedFile.readAsBytes();
      final result = await _detector.processFrame(bytes);

      if (mounted) {
        setState(() {
          _processedFrame = result.processedFrame;
          _dotCount = result.dotCount;
          _maxDots = result.maxDots;
        });
      }

      // Show result in a dialog so user can review before going back to camera
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.black,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Detected: ${result.dotCount} dots',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Image.memory(result.processedFrame),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close & Resume Camera',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    } finally {
      // Always resume camera stream after dialog is dismissed
      if (_cameraController.value.isInitialized &&
          !_cameraController.value.isStreamingImages) {
        await _cameraController.startImageStream(_onFrameAvailable);
      }
    }
  }

  Future<void> _initCamera() async {
    // Use the back camera (index 0)
    _cameraController = CameraController(
      widget.cameras[0],
      ResolutionPreset.low, // faster processing
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController.initialize();

    // Start streaming frames — like your while True: cap.read() loop
    await _cameraController.startImageStream(_onFrameAvailable);

    if (mounted) setState(() => _cameraReady = true);
  }

  void _onFrameAvailable(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // Run conversion + detection in an isolate-friendly way
      final jpegBytes = await _convertYuvToJpeg(image);
      if (jpegBytes == null) return;

      final result = await _detector.processFrame(jpegBytes);

      if (mounted) {
        setState(() {
          _processedFrame = result.processedFrame;
          _dotCount = result.dotCount;
          _maxDots = result.maxDots;
        });
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<Uint8List?> _convertYuvToJpeg(CameraImage cameraImage) async {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;

      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final int uvRowStride = uPlane.bytesPerRow;
      final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

      // Create an RGB image using the `image` package
      final rgbImage = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yPlane.bytesPerRow + x;
          final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          final int yVal = yBytes[yIndex];
          final int uVal = uBytes[uvIndex] - 128;
          final int vVal = vBytes[uvIndex] - 128;

          // YUV to RGB conversion
          int r = (yVal + 1.370705 * vVal).round().clamp(0, 255);
          int g = (yVal - 0.337633 * uVal - 0.698001 * vVal).round().clamp(
            0,
            255,
          );
          int b = (yVal + 1.732446 * uVal).round().clamp(0, 255);

          rgbImage.setPixelRgb(x, y, r, g, b);
        }
      }

      // Encode to JPEG
      final jpeg = img.encodeJpg(rgbImage, quality: 85);
      return Uint8List.fromList(jpeg);
    } catch (e) {
      debugPrint('YUV conversion error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _cameraController.stopImageStream();
    _cameraController.dispose();
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Domino Dot Scanner'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // NEW: gallery button
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: 'Test with image',
            onPressed: _pickAndProcessImage,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _detector.resetMax(),
            tooltip: 'Reset Max',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCard(
                  label: 'Current Dots',
                  value: '$_dotCount',
                  color: Colors.cyanAccent,
                ),
                _StatCard(
                  label: 'Max Dots',
                  value: '$_maxDots',
                  color: Colors.orangeAccent,
                ),
              ],
            ),
          ),
          // Main view — shows processed frame with dot circles drawn
          Expanded(
            child: _cameraReady
                ? _processedFrame != null
                      ? Image.memory(
                          _processedFrame!,
                          fit: BoxFit.contain,
                          gaplessPlayback:
                              true, // prevents flicker between frames
                        )
                      : CameraPreview(_cameraController)
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
