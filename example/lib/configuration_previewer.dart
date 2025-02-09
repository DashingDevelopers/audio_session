import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool playInterrupted = false;
  final _player = ja.AudioPlayer(
    // Handle audio_session events ourselves for the purpose of this demo.
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
    handleAudioSessionActivation: false,
  );

  ASConfig _selectedConfiguration = ASConfig.app_event;

  double outputVolume = 0.5;

  @override
  void initState() {
    super.initState();
    _initializeAudioSession();
  }

  Future<void> _initializeAudioSession() async {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(_selectedConfiguration.configuration);
    _handleInterruptions(audioSession);
    await _player.setUrl("https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3");
    await _player.setVolume(outputVolume);
  }

  void _handleInterruptions(AudioSession audioSession) {
    audioSession.becomingNoisyEventStream.listen((_) {
      debugPrint('becoming noisy - PAUSE');
      _player.pause();
    });
    _player.playingStream.listen((playing) {
      if (playing) {
        if (_selectedConfiguration.requestsFocus) audioSession.setActive(true);
        if (playInterrupted) {
          setState(() {
            playInterrupted = false;
          });
        }
      } else if (_selectedConfiguration.requestsFocus) audioSession.setActive(false);
    });
    audioSession.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (audioSession.androidAudioAttributes!.usage == AndroidAudioUsage.game) {
              _player.setVolume(_player.volume / 2);
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_player.playing) {
              _player.pause();
              setState(() {
                playInterrupted = true;
              });
            }
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(min(1.0, _player.volume * 2));
            break;
          case AudioInterruptionType.pause:
            if (playInterrupted) {
              _player.play();
              setState(() {
                playInterrupted = false;
              });
            }
            break;
          case AudioInterruptionType.unknown:
            if (playInterrupted) {
              setState(() {
                playInterrupted = false;
              });
            }
            break;
        }
      }
    });

    audioSession.devicesChangedEventStream.listen((event) {
      debugPrint('Devices added: ${event.devicesAdded}');
      debugPrint('Devices removed: ${event.devicesRemoved}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('audio_session example'),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Configuration: '),
                  DropdownButton<ASConfig>(
                    value: _selectedConfiguration,
                    items: ASConfig.values
                        .map((config) => DropdownMenuItem(
                              value: config,
                              child: Text(config.toString().split('.').last),
                            ))
                        .toList(),
                    onChanged: (value) async {
                      if (value != null) {
                        setState(() {
                          _selectedConfiguration = value;
                        });
                        final audioSession = await AudioSession.instance;
                        await audioSession.configure(_selectedConfiguration.configuration);
                      }
                    },
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: StreamBuilder<ja.PlayerState>(
                    stream: _player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      if (playerState?.processingState != ja.ProcessingState.ready) {
                        return Container(
                          margin: EdgeInsets.all(8.0),
                          width: 64.0,
                          height: 64.0,
                          child: CircularProgressIndicator(),
                        );
                      } else if (playerState?.playing == true) {
                        return IconButton(
                          icon: Icon(Icons.pause),
                          iconSize: 64.0,
                          onPressed: _player.pause,
                        );
                      } else {
                        return IconButton(
                          icon: Icon(Icons.play_arrow, color: playInterrupted ? Colors.red : null),
                          iconSize: 64.0,
                          onPressed: _player.play,
                        );
                      }
                    },
                  ),
                ),
              ),
              Slider(
                value: outputVolume,
                min: 0.0,
                max: 1.0,
                onChanged: (value) {
                  setState(() {
                    outputVolume = value;
                    _player.setVolume(outputVolume);
                  });
                },
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('is play interrupted?: $playInterrupted'),
                ),
              ),
              Expanded(
                child: FutureBuilder<AudioSession>(
                  future: AudioSession.instance,
                  builder: (context, snapshot) {
                    final session = snapshot.data;
                    if (session == null) return SizedBox();
                    return StreamBuilder<Set<AudioDevice>>(
                      stream: session.devicesStream,
                      builder: (context, snapshot) {
                        final devices = snapshot.data ?? {};
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text("Input devices", style: Theme.of(context).textTheme.titleLarge),
                            for (var device in devices.where((device) => device.isInput))
                              Text('${device.name} (${device.type.name})'),
                            SizedBox(height: 16),
                            Text("Output devices", style: Theme.of(context).textTheme.titleLarge),
                            for (var device in devices.where((device) => device.isOutput))
                              Text('${device.name} (${device.type.name})'),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ASConfig {
  app_event(requestsFocus: false), //TODO could go in core @Ryan?
  tts_voice_over(requestsFocus: true),
  music(requestsFocus: true),
  speech(requestsFocus: true);

  final bool requestsFocus;

  const ASConfig({required bool this.requestsFocus});

  AudioSessionConfiguration get configuration {
    switch (this) {
      case music:
        return AudioSessionConfiguration.music();
      case speech:
        return AudioSessionConfiguration.speech();
      case ASConfig.app_event:
        return AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          // androidAudioFocusGainType: AndroidAudioFocusGainType.gain, //gain ignored as focus not requested
          androidWillPauseWhenDucked: false,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.alarm, //or alarm ( try DND)
            // usage: AndroidAudioUsage.assistanceSonification, //or alarm ( try DND)
          ),
        );

      //for apple, change the session config depending on sound type (i guess ducking is fine during TTS as the alarm will not be affected)
      case ASConfig.tts_voice_over:
        return AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
          //AVAudioSessionCategoryOptions mixwithothers wont sound good for music with lyrics, possibly have this as an option for no vocal music
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,

          avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,

          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
          //ignored as focus not requested

          androidWillPauseWhenDucked: true,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.assistanceAccessibility,
          ),
        );
    }
  }
}
