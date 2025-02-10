import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;

/*

This example demonstrates how to use the audio_session package to experiment the audio session for different use cases.
And to make sure ducking etc works as expected.

See  the enum ASConfig at the end of this file for the different configurations that can be tested & extended

 */
void main() {
  runApp(const ConfigExperiementsExample());
}

class ConfigExperiementsExample extends StatefulWidget {
  const ConfigExperiementsExample({super.key});

  @override
  State<ConfigExperiementsExample> createState() => _ConfigExperiementsExampleState();
}

class _ConfigExperiementsExampleState extends State<ConfigExperiementsExample> {
  bool playInterruptedByExternalInterruption = false;
  final _player = ja.AudioPlayer(
    // Handle audio_session events ourselves for the purpose of this demo.
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
    handleAudioSessionActivation: false,
  );

  ASConfig _selectedConfiguration = ASConfig.app_event_alarm;

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
        if (_selectedConfiguration.requestsActiveFocus) {
          audioSession.setActive(true);
        }
        if (playInterruptedByExternalInterruption) {
          setState(() {
            playInterruptedByExternalInterruption = false;
          });
        }
        //else not playing
      } else if (_selectedConfiguration.requestsActiveFocus) {
        //if this audio session has requested focus, and therefor ducked others, then deactivate the session
        //this may not be desired behaviour for all apps
        bool shouldDeactivateInAndroidOnPause = false;
        if (Platform.isAndroid) {
          audioSession.setActive(false);
        } else {
          Future.delayed(Duration(seconds: 2), () async {
            //older iOS devices don't have time for the AVplayer to release the audio session, so this 2 second delay is needed for those devices
            //similar situation to an old bug relating to deactivating a stopped audio session
            //error output:
            //[ERROR:flutter/runtime/dart_vm_initializer.cc(41)] Unhandled Exception: PlatformException(560030580, The operation couldn’t be completed. (OSStatus error 560030580.), null, null)
            await audioSession.setActive(false);
          });
        }
      }
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
                playInterruptedByExternalInterruption = true;
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
            if (playInterruptedByExternalInterruption) {
              _player.play();
              setState(() {
                playInterruptedByExternalInterruption = false;
              });
            }
            break;
          case AudioInterruptionType.unknown:
            if (playInterruptedByExternalInterruption) {
              setState(() {
                playInterruptedByExternalInterruption = false;
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
          title: const Text('audio_session config experiments'),
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
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(Icons.pause),
                              iconSize: 64.0,
                              onPressed: _player.pause,
                            ),
                            IconButton(
                                icon: Icon(Icons.stop),
                                iconSize: 64.0,
                                onPressed: () async {
                                  await _player.stop();
                                  //reset the player session config and audio session so that it can be played again
                                  _initializeAudioSession();
                                }),
                          ],
                        );
                      } else {
                        return IconButton(
                            icon: Icon(Icons.play_arrow,
                                color: playInterruptedByExternalInterruption ? Colors.red : null),
                            iconSize: 64.0,
                            onPressed: _player.play);
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
                  child: Text(
                    'is play interrupted from other app?: $playInterruptedByExternalInterruption',
                    style: TextStyle(color: Colors.purple),
                  ),
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
  app_event_alarm(requestsActiveFocus: false),//audio to be mixed with external apps audio
  tts_voice_over(requestsActiveFocus: true),//external apps audio to be ducked
  music(requestsActiveFocus: true),//external apps audio to be stopped/paused
  speech(requestsActiveFocus: true);//external apps audio to be stopped/paused

  final bool
      requestsActiveFocus;  //if true, external app playing audio that handle events will be
                      // ducked, paused or stopped whilst this is playing, and unducked or resumed when this apps audio
                      // is stopped or paused

  const ASConfig({required bool this.requestsActiveFocus});

  AudioSessionConfiguration get configuration {
    switch (this) {
      case music:
        return AudioSessionConfiguration.music();
      case speech:
        return AudioSessionConfiguration.speech();
      case ASConfig.app_event_alarm:
        return AudioSessionConfiguration(
          //ios
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          //android
          // androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          //note - default gain is effectively ignored as app_event_alarm will not request active focus
          androidWillPauseWhenDucked: false,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.alarm,
            // usage: AndroidAudioUsage.assistanceSonification,//may be more appropriate than alarm
          ),
        );

      case ASConfig.tts_voice_over:
        return AudioSessionConfiguration(
          //ios
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          //AVAudioSessionCategoryOptions mixWithOthers for background non vocal music
          //AVAudioSessionCategoryOptions duckOthers for background music with lyrics
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,

          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: true,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.assistanceAccessibility,
          ),
        );
    }
  }
}
