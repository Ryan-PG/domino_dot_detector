import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class DotDetectionResult {
  final int dotCount;
  final int maxDots;
  final Uint8List processedFrame;

  DotDetectionResult({
    required this.dotCount,
    required this.maxDots,
    required this.processedFrame,
  });
}

class DotDetector {
  int _maxDots = 0;
  late cv.SimpleBlobDetector _detector;

  DotDetector() {
    _initDetector();
  }

  void _initDetector() {
    // Mirror of your Python SimpleBlobDetector_Params
    final params = cv.SimpleBlobDetectorParams.empty();

    params.filterByArea = true;
    params.minArea = 50;
    params.maxArea = 5000;

    params.filterByCircularity = true;
    params.minCircularity = 0.8;

    params.filterByConvexity = true;
    params.minConvexity = 0.9;

    params.filterByInertia = true;
    params.minInertiaRatio = 0.9;

    _detector = cv.SimpleBlobDetector.create(params);
  }

  /// Main processing function — mirrors your process_frame() in Python
  Future<DotDetectionResult> processFrame(Uint8List jpegBytes) async {
    // Decode the JPEG frame to a cv.Mat
    final mat = cv.imdecode(jpegBytes, cv.IMREAD_COLOR);

    // 1. Convert to HSV — same as cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    final hsv = await cv.cvtColorAsync(mat, cv.COLOR_BGR2HSV);

    // 2. Create yellow mask — same as cv2.inRange(hsv, lower_yellow, upper_yellow)
    final lowerYellow = cv.Mat.fromScalar(
      1,
      1,
      cv.MatType.CV_8UC3,
      cv.Scalar(15, 100, 100),
    );
    final upperYellow = cv.Mat.fromScalar(
      1,
      1,
      cv.MatType.CV_8UC3,
      cv.Scalar(35, 255, 255),
    );
    final yellowMask = await cv.inRangeAsync(hsv, lowerYellow, upperYellow);

    // 3. Invert yellow mask — same as cv2.bitwise_not(yellow_mask)
    final nonYellowMask = await cv.bitwiseNOTAsync(yellowMask);

    // 4. Apply mask to original — same as cv2.bitwise_and(frame, frame, mask=non_yellow_mask)
    final nonYellowImage = await cv.bitwiseANDAsync(
      mat,
      mat,
      mask: nonYellowMask,
    );

    // 5. Detect blobs
    final keypoints = await _detector.detectAsync(nonYellowImage);

    // 6. Draw circles around detected dots
    final resultMat = mat.clone();
    for (final kp in keypoints) {
      final center = cv.Point(kp.x.toInt(), kp.y.toInt());
      final radius = (kp.size / 2).toInt();
      cv.circle(
        resultMat,
        center,
        radius,
        cv.Scalar(0, 255, 255),
        thickness: 3,
      );
    }

    // 7. Update dot count
    final numDots = keypoints.length;
    if (numDots == 0) {
      _maxDots = 0;
    } else if (numDots > _maxDots) {
      _maxDots = numDots;
    }

    // 8. Draw text overlay
    // cv.putText(
    //   resultMat,
    //   'Dots: $numDots (Max: $_maxDots)',
    //   cv.Point(20, 40),
    //   cv.FONT_HERSHEY_SIMPLEX,
    //   1.0,
    //   cv.Scalar(255, 0, 0),
    //   thickness: 3,
    // );

    // 9. Encode result back to bytes for display
    final encoded = cv.imencode('.jpg', resultMat);

    // Cleanup
    mat.dispose();
    hsv.dispose();
    yellowMask.dispose();
    nonYellowMask.dispose();
    nonYellowImage.dispose();
    resultMat.dispose();

    return DotDetectionResult(
      dotCount: numDots,
      maxDots: _maxDots,
      processedFrame: encoded.$2,
    );
  }

  void resetMax() => _maxDots = 0;

  void dispose() {
    _detector.dispose();
  }
}
