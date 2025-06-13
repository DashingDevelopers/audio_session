import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;

/*

This example demonstrates how to use the audio_session package to experiment the audio session for different use cases.
And to make sure ducking etc works as expected.

See  the enum ASConfig at the end of this file for the different configurations that can be tested & extended

This also has enhanced controls to show when audio has been paused by external event by coloring the play button red.

 */
void main() {
  runApp(const InteruptionStreamConsole());
}

class InteruptionStreamConsole extends StatefulWidget {
  const InteruptionStreamConsole({super.key});

  @override
  State<InteruptionStreamConsole> createState() => _InteruptionStreamConsoleState();
}



class _InteruptionStreamConsoleState extends State<InteruptionStreamConsole> {
  bool mp3PlayerInterrupted = false;
  bool silencePlayerInterrupted = false;
  final _eventsLog = <String>[];
  final _mp3UrlPlayer = ja.AudioPlayer(
    // Handle audio_session events ourselves for the purpose of this demo.
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
    handleAudioSessionActivation: false,
  );

  final _silenceLooper = ja.AudioPlayer(
    // Handle audio_session events ourselves for the purpose of this demo.
    handleInterruptions: false,
    androidApplyAudioAttributes: false,
    handleAudioSessionActivation: true,
  );

  ASConfig _selectedConfiguration = ASConfig.no_focus_no_ducking;

  double mp3OutputVolume = 0.5;
  double silenceOutputVolume = 0.5;

  @override
  void initState() {
    super.initState();
    _initializeAudioSession();
  }

  Future<void> _initializeAudioSession() async {
    final audioSession = await AudioSession.instance;
    _handleInterruptions(audioSession);
    await _mp3UrlPlayer.setUrl("https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3");
    await _mp3UrlPlayer.setVolume(mp3OutputVolume);

    await _silenceLooper.setAsset('assets/slow-spring-board.mp3');
    await _silenceLooper.setVolume(silenceOutputVolume);
    await _silenceLooper.setLoopMode(ja.LoopMode.one); //loop the silence
    await _silenceLooper.setAndroidAudioAttributes(ASConfig.no_focus_no_ducking.configuration.androidAudioAttributes!);
  }

  void _handleInterruptions(AudioSession audioSession) {
    audioSession.becomingNoisyEventStream.listen((_) {
      addToEventLog('becoming noisy - PAUSE');
      _mp3UrlPlayer.pause();
    });

    _mp3UrlPlayer.playingStream.listen((playing) {
      if (playing) {
        if (_selectedConfiguration.requestsActiveFocus) {
          addToEventLog('mp3stream activating audiosession');
          audioSession.setActive(true);
        }
        if (mp3PlayerInterrupted) {
          setState(() {
            mp3PlayerInterrupted = false;
          });
        }
        //else not playing
      } else if (_selectedConfiguration.requestsActiveFocus) {
        //if this audio session has requested focus, and therefor ducked others, then deactivate the session
        //this may not be desired behaviour for all apps
        bool shouldDeactivateInAndroidOnPause = false;
        if (Platform.isAndroid) {
          addToEventLog('mp3stream deactivating audiosession');

          audioSession.setActive(false);
        } else {
          addToEventLog('mp3stream deactivating audiosession in 2 seconds');

          Future.delayed(Duration(seconds: 2), () async {
            //older iOS devices (up to at least ios14) don't have time for the AVplayer to release the audio session, so this 2 second delay is needed for those devices
            //similar situation to an old bug relating to deactivating a stopped audio session in audio service - https://github.com/ryanheise/audio_service/issues/672
            //error output:
            //[ERROR:flutter/runtime/dart_vm_initializer.cc(41)] Unhandled Exception: PlatformException(560030580, The operation couldn’t be completed. (OSStatus error 560030580.), null, null)
            addToEventLog('mp3stream deactivating audiosession');

            await audioSession.setActive(false);
          });
        }
      }
    });

    audioSession.interruptionEventStream.listen((event) {
      addToEventLog('interruptionEventStream event: ${event.begin ? 'begin' : 'end'} type: ${event.type}');
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (audioSession.androidAudioAttributes!.usage == AndroidAudioUsage.game) {
              _mp3UrlPlayer.setVolume(_mp3UrlPlayer.volume / 2);
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_mp3UrlPlayer.playing) {
              _mp3UrlPlayer.pause();
              setState(() {
                mp3PlayerInterrupted = true;
              });
            }
            if (_silenceLooper.playing) {
              _silenceLooper.pause(); //device player will be paused, so let jaPlayer know its paused too.
              setState(() {
                silencePlayerInterrupted = true;
              });
            }

            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _mp3UrlPlayer.setVolume(min(1.0, _mp3UrlPlayer.volume * 2));
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (mp3PlayerInterrupted) {
              _mp3UrlPlayer.play();
               audioSession.configure(_selectedConfiguration.configuration);

              setState(() {
                mp3PlayerInterrupted = false;
              });
            }
            if (silencePlayerInterrupted) {
              _silenceLooper.play();
              setState(() {
                silencePlayerInterrupted = false;
              });
            }

            break;
        }
      }
    });

    audioSession.devicesChangedEventStream.listen((event) {
      addToEventLog('Devices added: ${event.devicesAdded}');
      addToEventLog('Devices removed: ${event.devicesRemoved}');
    });
  }

  void addToEventLog(String event) {
    final time = DateTime.now();
    final formattedTime =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    setState(() {
      _eventsLog.add('$formattedTime $event');
    });
    debugPrint(event);
  }

  void clearEventLog() {
    setState(() {
      _eventsLog.clear();
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

                        // _initializeAudioSession(); //reinitialize the audio session with the new listener configuration
                        final audioSession = await AudioSession.instance;
                        await audioSession.configure(_selectedConfiguration.configuration);
                      }
                    },
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlayerControls(
                      title: 'mp3 url',
                      player: _mp3UrlPlayer,
                      interruptedByInterruptionEventStream: mp3PlayerInterrupted,
                  ),
                  Column(
                    children: [
                      PlayerControls(
                          title: 'silence looper',
                          player: _silenceLooper,
                          interruptedByInterruptionEventStream: mp3PlayerInterrupted),
                      Row(
                        children: [
                          Icon(silenceOutputVolume == 0 ? Icons.volume_mute : Icons.volume_up),
                          Switch(
                            value: silenceOutputVolume != 0,
                            onChanged: (value) {
                              setState(() {
                                if (value) {
                                  silenceOutputVolume = 0.5;
                                  _silenceLooper.setVolume(silenceOutputVolume);
                                } else {
                                  silenceOutputVolume = 0;
                                  _silenceLooper.setVolume(silenceOutputVolume);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Interrupted from interruptionEventStream?: $mp3PlayerInterrupted',
                    style: TextStyle(color: Colors.purple),
                  ),
                ),
              ),
              Divider(),
              TextButton(
                onPressed: () async {
                  clearEventLog();
                },
                child: Text('Clear Log'),
              ),
              Expanded(
                child: Container(
                  color: Colors.grey,
                  child: _eventsLog.isEmpty
                      ? Center(child: Text('No events logged yet'))
                      : ListView.builder(
                          itemCount: _eventsLog.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(_eventsLog[index]),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required ja.AudioPlayer player,
    required this.interruptedByInterruptionEventStream,
    required String this.title,
  }) : _player = player;

  final ja.AudioPlayer _player;
  final bool interruptedByInterruptionEventStream;

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(child: Text(title)),
        StreamBuilder<ja.PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final playerState = snapshot.data;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Text('Player State: ${playerState?.processingState.name}'),
                        Text('Player Playing: ${playerState?.playing}'),
                      ],
                    ),
                  ),
                  if (playerState?.processingState == ja.ProcessingState.buffering ||
                      playerState?.processingState == ja.ProcessingState.loading)
                    PlayerLoading()
                  else if (playerState?.playing == true)
                    PlayerPlaying(
                        interruptedByInterruptionEventStream: interruptedByInterruptionEventStream, player: _player)
                  else
                    PlayerReady(
                      interruptedByInterruptionEventStream: interruptedByInterruptionEventStream,
                      player: _player,
                    ),
                ],
              );
            }),
      ],
    );
  }
}

class PlayerReady extends StatelessWidget {
  const PlayerReady({
    super.key,
    required this.interruptedByInterruptionEventStream,
    required ja.AudioPlayer player,
  }) : _player = player;

  final bool interruptedByInterruptionEventStream;
  final ja.AudioPlayer _player;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            icon: Icon(Icons.play_arrow, color: interruptedByInterruptionEventStream ? Colors.red : null),
            iconSize: 64.0,
            onPressed: _player.play),
        IconButton(
            icon: Icon(Icons.stop),
            iconSize: 64.0,
            onPressed: () async {
              await _player.stop(); //stops and rewinds
            }),
      ],
    );
  }
}

class PlayerPlaying extends StatelessWidget {
  const PlayerPlaying({
    super.key,
    required ja.AudioPlayer player,
    required this.interruptedByInterruptionEventStream,
  }) : _player = player;

  final ja.AudioPlayer _player;

  final bool interruptedByInterruptionEventStream;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.pause, color: interruptedByInterruptionEventStream ? Colors.red : null),
          iconSize: 64.0,
          onPressed: _player.pause,
        ),
        IconButton(
            icon: Icon(Icons.stop),
            iconSize: 64.0,
            onPressed: () async {
              await _player.stop();
            }),
      ],
    );
  }
}

class PlayerLoading extends StatelessWidget {
  const PlayerLoading({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(8.0),
      width: 64.0,
      height: 64.0,
      child: CircularProgressIndicator(),
    );
  }
}

enum ASConfig {
  no_focus_no_ducking(requestsActiveFocus: false), //audio to be mixed with external apps audio
  duck_or_interupt_spoken(requestsActiveFocus: true), //external apps audio to be ducked
  music(requestsActiveFocus: true), //external apps audio to be stopped/paused
  speech(requestsActiveFocus: true); //external apps audio to be stopped/paused

  final bool requestsActiveFocus; //if true, external app playing audio that handle events will be
  // ducked, paused or stopped whilst this is playing, and unducked or resumed when this apps audio
  // is stopped or paused

  const ASConfig({required bool this.requestsActiveFocus});

  AudioSessionConfiguration get configuration {
    switch (this) {
      case music:
        return AudioSessionConfiguration.music();
      case speech:
        return AudioSessionConfiguration.speech();
      case ASConfig.no_focus_no_ducking:
        return AudioSessionConfiguration(
          //ios
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          //android

          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          //default is gain
          //note - gaintype is effectively ignored as no_focus_example will not request active focus
          androidWillPauseWhenDucked: false,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.sonification,
            usage: AndroidAudioUsage.alarm,
            // usage: AndroidAudioUsage.assistanceSonification,//may be more appropriate than alarm
          ),
        );

      case ASConfig.duck_or_interupt_spoken:
        return AudioSessionConfiguration(
          //ios
          avAudioSessionCategory: AVAudioSessionCategory.ambient,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers |
              AVAudioSessionCategoryOptions.interruptSpokenAudioAndMixWithOthers,
          //ducks music, interrupts spoken audio
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
