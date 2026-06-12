import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final bool isMe;

  const AudioPlayerWidget({
    super.key,
    required this.audioUrl,
    required this.isMe,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final AudioPlayer _audioPlayer;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _completionSubscription;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
        });
      }
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _completionSubscription = _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _playerState = PlayerState.completed;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _completionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playPause() async {
    if (_playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.audioUrl));
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final themePrimaryColor = widget.isMe ? ObsidianMintColors.onPrimary : ObsidianMintColors.primary;
    final themeSecondaryColor = widget.isMe
        ? ObsidianMintColors.onPrimary.withValues(alpha: 0.6)
        : ObsidianMintColors.textSecondary;

    final isPlaying = _playerState == PlayerState.playing;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 32,
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              color: themePrimaryColor,
            ),
            onPressed: _playPause,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: themePrimaryColor,
                    inactiveTrackColor: themePrimaryColor.withValues(alpha: 0.2),
                    thumbColor: themePrimaryColor,
                    trackHeight: 3.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                  ),
                  child: Slider(
                    value: (_position.inMilliseconds > 0 &&
                            _duration.inMilliseconds > 0 &&
                            _position.inMilliseconds <= _duration.inMilliseconds)
                        ? _position.inMilliseconds.toDouble()
                        : 0.0,
                    min: 0.0,
                    max: _duration.inMilliseconds > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (value) async {
                      final newDuration = Duration(milliseconds: value.toInt());
                      await _audioPlayer.seek(newDuration);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(
                          fontSize: 10,
                          color: themeSecondaryColor,
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(
                          fontSize: 10,
                          color: themeSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
