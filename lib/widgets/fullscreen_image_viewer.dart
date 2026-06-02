import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A full-screen single image viewer that fills the screen
/// and supports pinch-to-zoom without gesture conflicts.
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.imagePath,
  });

  final String imagePath;

  static void show(
    BuildContext context, {
    required String imagePath,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullscreenImageViewer(imagePath: imagePath);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  final TransformationController _controller = TransformationController();
  double _currentScale = 1.0;
  ui.Image? _image;
  Size _imageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadImageInfo();
  }

  Future<void> _loadImageInfo() async {
    final file = File(widget.imagePath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _image = frame.image;
        _imageSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_currentScale > 1.01) {
      _controller.value = Matrix4.identity();
      setState(() => _currentScale = 1.0);
    } else {
      final zoomed = Matrix4.identity()..scale(2.5); // ignore: deprecated_member_use
      _controller.value = zoomed;
      setState(() => _currentScale = 2.5);
    }
  }

  bool get _isZoomed => _currentScale > 1.01;

  BoxFit _computeBoxFit() {
    if (_imageSize == Size.zero) return BoxFit.contain;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final imgW = _imageSize.width;
    final imgH = _imageSize.height;

    // If image is wider than screen ratio (landscape image), fill width
    if (imgW / imgH > screenW / screenH) {
      return BoxFit.fitWidth;
    }
    // Otherwise fill height
    return BoxFit.fitHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen image with InteractiveViewer
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1.0,
                maxScale: 5.0,
                constrained: true,
                onInteractionUpdate: (details) {
                  final newScale = _controller.value.getMaxScaleOnAxis();
                  if ((newScale - _currentScale).abs() > 0.01) {
                    setState(() => _currentScale = newScale);
                  }
                },
                onInteractionEnd: (details) {
                  final newScale = _controller.value.getMaxScaleOnAxis();
                  if (newScale < 1.01) {
                    _controller.value = Matrix4.identity();
                    setState(() => _currentScale = 1.0);
                  } else {
                    setState(() => _currentScale = newScale);
                  }
                },
                child: SizedBox.expand(
                  child: Image.file(
                    File(widget.imagePath),
                    fit: _computeBoxFit(),
                    alignment: Alignment.center,
                    errorBuilder: (_, error, __) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.broken_image,
                                color: Colors.white38, size: 64),
                            const SizedBox(height: 8),
                            Text(
                              '图片加载失败',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Top bar with close button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                bottom: 8,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (_isZoomed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_currentScale.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),

          // Bottom hint
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isZoomed ? '双击还原 · 双指缩放' : '双击放大 · 双指缩放',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
