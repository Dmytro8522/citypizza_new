import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class OnboardingVideo extends StatelessWidget {
  final VideoPlayerController controller;
  const OnboardingVideo({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (!controller.value.isInitialized) {
      return SizedBox(height: size.height * 0.6);
    }
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(41),
        bottomRight: Radius.circular(41),
      ),
      child: SizedBox(
        height: size.height * 0.6,
        width: size.width,
        child: VideoPlayer(controller),
      ),
    );
  }
}
