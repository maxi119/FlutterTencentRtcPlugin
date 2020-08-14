import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:tencent_rtc_plugin/enums/listener_type_enum.dart';
import 'package:tencent_rtc_plugin/tencent_rtc_plugin.dart';
import 'logger.dart';

// mockable tencent trc

enum AudioRoute { Speaker, Earphone }

/// RoomType
///
/// 0 Video Call
/// 1 Live Stream   廣播，略有延遲
/// 2 Audio Call
/// 3 Voice Chat    廣播，略有延遲
enum RoomType {
  VideoCall,
  LiveStream,
  AudioCall,
  VoiceChat,
}

abstract class TencentRtcEventHandler {
  void onRemoteUserEnterRoom(String userId);
  void onSDKError(String msg, int code);
  void onUserAudioAvailable(String userId, bool available);
  void onMicReady();
  void onRecvCustomMessage(String userId, int seq, int cmdId, String data);
  void onUserVoiceVolume(List<dynamic> userVolumes, int totalVolume);
}

class TencentRtcHelper {
  factory TencentRtcHelper() => _inst;
  TencentRtcHelper._inter() {
    TencentRtcPlugin.init();
    _addListener(_onRtcListener);
  }

  static TencentRtcHelper _inst = TencentRtcHelper._inter();

  static void replace(TencentRtcHelper inst) {
    logger.d('rtc replace service');
    _inst = inst;
  }

  Completer<int> _compEnterRoom;
  Completer<bool> _compExitRoom;
  Completer<AudioRoute> _compRouteChanged;
  TencentRtcEventHandler _handler;
  set setEventHandler(TencentRtcEventHandler handler) => _handler = handler;

  //	0：不显示；1：显示精简版；2：显示全量版，默认为不显示
  void showDebugView({int mode = 0}) {
    TencentRtcPlugin.showDebugView(mode: mode);
  }

  void setConsoleEnabled({bool enabled}) {
    TencentRtcPlugin.setConsoleEnabled(enabled: enabled);
  }

  void _addListener(ListenerValue func) {
    TencentRtcPlugin.addListener(func);
  }

  void setDefaultStreamRecvMode({bool autoRecvAudio, bool autoRecvVideo}) {
    TencentRtcPlugin.setDefaultStreamRecvMode(autoRecvAudio: autoRecvAudio, autoRecvVideo: autoRecvVideo);
  }

  void startLocalAudio({bool enableVolumeEvaluation, int intervalMs = 100}) {
    if (enableVolumeEvaluation) {
      TencentRtcPlugin.enableAudioVolumeEvaluation(intervalMs: intervalMs);
    }
    TencentRtcPlugin.startLocalAudio();
  }

  void stopLocalAudio() {
    TencentRtcPlugin.stopLocalAudio();
  }

  void _removeListener(ListenerValue func) {
    TencentRtcPlugin.removeListener(func);
  }

  Future<bool> exitRoom() async {
    _compExitRoom = Completer<bool>();
    TencentRtcPlugin.exitRoom();
    return _compExitRoom.future;
  }

  Future<AudioRoute> setAudioRoute({AudioRoute route}) {
    TencentRtcPlugin.setAudioRoute(route: route.index);
    _compRouteChanged = Completer<AudioRoute>();
    return _compRouteChanged.future;
  }

  Future<int> enterRoom({
    @required int appid, // appid
    @required String userId, // 用户id
    @required String userSig, // 用户签名
    @required int roomId, // 房间号
    @required int scene, // 应用场景，目前支持视频通话（VideoCall）和在线直播（Live）两种场景。
    int role, // 角色
    String privateMapKey, // 房间签名 [非必填]
  }) async {
    TencentRtcPlugin.enterRoom(
      appid: appid,
      userId: userId,
      userSig: userSig,
      roomId: roomId,
      scene: scene,
      role: role,
      privateMapKey: privateMapKey,
    );
    _compEnterRoom = Completer<int>();
    return _compEnterRoom.future;
  }

  void _onRtcListener(ListenerTypeEnum type, dynamic param) {
    // 用户上传视频监听

    if ([ListenerTypeEnum.NetworkQuality, ListenerTypeEnum.Statistics].contains(type) == false) {
      logger.v('rtx: onListen $type');
      logger.v('rtx: onListen param $param');
    }
    var paramObj = {};
    try {
      if (param != null) {
        paramObj = jsonDecode(param);
      }
    } on Exception catch (_) {}

    switch (type) {
      case ListenerTypeEnum.SdkError:
        logger.e('RTC error $param');
        //{"msg":"进房失败sdkappid in usersig unmatch","code":-100018}
        _handler?.onSDKError(param['msg'], param['code']);
        break;
      case ListenerTypeEnum.RemoteUserEnterRoom:
        break;
      case ListenerTypeEnum.EnterRoom:
        // TRTCNetwork
        _compEnterRoom?.complete(param as int); // > 0 ok
        _compEnterRoom = null;
        break;
      case ListenerTypeEnum.ExitRoom:
        _compExitRoom?.complete(true);
        _compExitRoom = null;
        break;
      case ListenerTypeEnum.RemoteUserLeaveRoom:
        final String userId = paramObj['userId'];
        logger.d('remoteUserLeave $userId: ${paramObj["reason"]}');
        _handler?.onRemoteUserEnterRoom(userId);
        break;
      case ListenerTypeEnum.UserAudioAvailable:
        final String userId = paramObj['userId'];
        final available = paramObj['available'] as bool;
        _handler?.onUserAudioAvailable(userId, available);
        break;
      case ListenerTypeEnum.MicDidReady:
        _handler?.onMicReady();
        break;
      case ListenerTypeEnum.AudioRouteChanged:
        final newOne = paramObj['newRoute'];
        final oldOne = paramObj['oldRoute'];
        print('route changed $newOne , $oldOne');
        AudioRoute route = AudioRoute.Speaker;
        if (newOne == 1) {
          route = AudioRoute.Earphone;
        }
        _compRouteChanged.complete(route);

        break;
      case ListenerTypeEnum.UserVoiceVolume:
        // { userId, volume }
        // voluem ~ 100
        final List<dynamic> userVolumes = paramObj['userVolumes'] as List<dynamic>;
        final totalVolume = paramObj['totalVolume'];
        _handler?.onUserVoiceVolume(userVolumes, totalVolume);

        break;
      case ListenerTypeEnum.RecvCustomCmdMsg:
        final String userId = paramObj['userId'] as String;
        final int cmdID = paramObj['cmdID'] as int;
        final int seq = paramObj['seq'] as int;
        final String message = paramObj['message'] as String;
        _handler.onRecvCustomMessage(userId, seq, cmdID, message);
        break;
      case ListenerTypeEnum.MissCustomCmdMsg:
        break;
      case ListenerTypeEnum.Statistics:
        /*
            "appCpu": statistics.appCpu,
            "systemCpu": statistics.systemCpu,
            "rtt": statistics.rtt,
            "upLoss": statistics.upLoss,
            "downLoss": statistics.downLoss,
            "sendBytes": statistics.sentBytes,
            "receiveBytes": statistics.receivedBytes,
            "localArray": localArray,
            "remoteArray": remoteArray

              // remote array
                "userId": item.userId,
                "finalLoss": item.finalLoss,
                "width": item.width,
                "height": item.height,
                "frameRate": item.frameRate,
                "videoBitrate": item.videoBitrate,
                "audioSampleRate": item.audioSampleRate,
                "audioBitrate": item.audioBitrate,
                "streamType": item.streamType.rawValue */

        break;
      default:
    }
  }
}
