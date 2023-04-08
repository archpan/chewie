import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:brightness_volume/brightness_volume.dart';



class VideoPlayerGestures extends StatefulWidget {
  const VideoPlayerGestures({Key? key, required this.videoPlayerController, required this.child, required this.onClick, required this.onDoubleClick, this.enableDrag = true}) : super(key: key);
  final VideoPlayerController videoPlayerController;
  final Widget child;
  final VoidCallback onClick;
  final VoidCallback onDoubleClick;
  final bool enableDrag;
  @override
  _VideoPlayerGesturesState createState() => _VideoPlayerGesturesState(videoPlayerController: videoPlayerController, child: child, onClick: onClick, onDoubleClick: onDoubleClick, enableDrag: enableDrag);
}

class _VideoPlayerGesturesState extends State<VideoPlayerGestures> {
  final VideoPlayerController videoPlayerController;
  final Widget child;
  final VoidCallback onClick;
  final VoidCallback onDoubleClick;
  final bool enableDrag;
  _VideoPlayerGesturesState({Key? key, required this.videoPlayerController, required this.child, required this.onClick, required this.onDoubleClick, required this.enableDrag});

  double _width = 0.0; // 组件宽度
  double _height = 0.0; // 组件高度
  late Offset _startPanOffset; //  滑动的起始位置
  late double _movePan; // 滑动的偏移量累计总和
  bool _brightnessOk = false; // 是否允许调节亮度
  bool _volumeOk = false; // 是否允许调节亮度
  bool _seekOk = false; // 是否允许调节播放进度
  double _brightnessValue = 0.0; // 设备当前的亮度
  double _volumeValue = 0.0; // 设备本身的音量
  Duration _positionValue = const Duration(seconds: 0); // 当前播放时间，以计算手势快进或快退
  late PercentageWidget _percentageWidget; // 快退、快进、音量、亮度的百分比，手势操作时显示的widget


  @override
  void initState() {
    // TODO: implement initState
    _percentageWidget = PercentageWidget();
    // _children.add(_percentageWidget);
    super.initState();
    _setInit();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      // // 单击上下widget隐藏与显示
      onDoubleTap: _onDoubleTap,
      // 双击暂停、播放
      onVerticalDragStart: !enableDrag ? null : _onVerticalDragStart,
      // 根据起始位置。确定是调整亮度还是调整声音
      onVerticalDragUpdate: !enableDrag ? null : _onVerticalDragUpdate,
      // 一般在更新的时候，同步调整亮度或声音
      onVerticalDragEnd: !enableDrag ? null : _onVerticalDragEnd,
      // 结束后，隐藏百分比提示信息widget
      onHorizontalDragStart: !enableDrag ? null : _onHorizontalDragStart,
      // 手势跳转播放起始位置
      onHorizontalDragUpdate: !enableDrag ? null : _onHorizontalDragUpdate,
      // 根据手势更新快进或快退
      onHorizontalDragEnd: !enableDrag ? null : _onHorizontalDragEnd,
      // 手势结束seekTo
      child: Container(
        // 保证手势全屏
        width: double.maxFinite,
        height: double.maxFinite,
        child:
        // child
        Stack(
          children: [child, _percentageWidget],
        ),
      ),
    );
  }

  void _setInit() async {
    debugPrint('[VideoPlayer] _setInit()');
    _volumeValue = await BVUtils.volume;
    _brightnessValue = await BVUtils.brightness;
  }



  // 设置亮度
  Future<void> setBrightness(double brightness) async {
    debugPrint('[VideoPlayer] setBrightness($brightness)');
    return await BVUtils.setBrightness(brightness);
  }


  void _onTap() {
    debugPrint('[VideoPlayer] _onTap()');
    onClick();
  }

  void _onDoubleTap() {
    onDoubleClick();
    debugPrint('[VideoPlayer] _onDoubleTap()');
  }

  void _onVerticalDragStart(DragStartDetails details) {
    debugPrint('[VideoPlayer] _onVerticalDragStart($details)');
    _resetPan();
    _startPanOffset = details.globalPosition;
    if (_startPanOffset.dx < _width * 0.5) {
      // 左边调整亮度
      _brightnessOk = true;
    } else {
      // 右边调整声音
      _volumeOk = true;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    debugPrint('[VideoPlayer] _onVerticalDragUpdate($details)');
    // 累计计算偏移量(下滑减少百分比，上滑增加百分比)
    _movePan += (-details.delta.dy);
    if (_startPanOffset.dx < (_width / 2)) {
      if (_brightnessOk) {
        double b = _getBrightnessValue();
        _percentageWidget.percentageCallback("亮度：${(b * 100).toInt()}%");
        BVUtils.setBrightness(b);
      }
    } else {
      if (_volumeOk) {
        double v = _getVolumeValue();
        _percentageWidget.percentageCallback("音量：${(v * 100).toInt()}%");
        BVUtils.setVolume(v);
      }
    }
  }

  void _onVerticalDragEnd(_) {
    debugPrint('[VideoPlayer] _onVerticalDragEnd()');
    // 隐藏
    _percentageWidget.offstageCallback(true);
    if (_volumeOk) {
      _volumeValue = _getVolumeValue();
      _volumeOk = false;
    } else if (_brightnessOk) {
      _brightnessValue = _getBrightnessValue();
      _brightnessOk = false;
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    debugPrint('[VideoPlayer] _onHorizontalDragStart()');
    _resetPan();
    _positionValue = videoPlayerController.value.position;
    _seekOk = true;
    onClick();
  }

  String _formatDuration(int second) {
    int min = second ~/ 60;
    int sec = second % 60;
    String minString = min < 10 ? "0$min" : min.toString();
    String secString = sec < 10 ? "0$sec" : sec.toString();
    return minString + ":" + secString;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    debugPrint('[VideoPlayer] _onHorizontalDragUpdate()');
    if (!_seekOk) return;
    debugPrint('[VideoPlayer]');
    _movePan += details.delta.dx;
    double value = _getSeekValue();
    // 简单处理下时间格式化mm:ss （超过1小时可自行处理hh:mm:ss）
    String currentSecond = _formatDuration((value * videoPlayerController.value.duration.inSeconds).toInt());
    if (_movePan >= 0) {
      _percentageWidget.percentageCallback("快进至：$currentSecond");
    } else {
      _percentageWidget.percentageCallback("快退至：$currentSecond");
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    debugPrint('[VideoPlayer] _onHorizontalDragUpdate() 1');
    if (!_seekOk) return;
    debugPrint('[VideoPlayer] _onHorizontalDragUpdate() 2');
    double value = _getSeekValue();
    int seek = (value * videoPlayerController.value.duration.inMilliseconds).toInt();
    videoPlayerController.seekTo(Duration(milliseconds: seek));
    _percentageWidget.offstageCallback(true);
    _seekOk = false;
  }

  // 计算亮度百分比
  double _getBrightnessValue() {
    double value = double.parse(
        (_movePan / _height + _brightnessValue).toStringAsFixed(2));
    if (value >= 1.00) {
      value = 1.00;
    } else if (value <= 0.00) {
      value = 0.00;
    }
    debugPrint('[VideoPlayer] _getBrightnessValue() $value');
    return value;
  }

  // 计算声音百分比
  double _getVolumeValue() {
    double value =
        double.parse((_movePan / _height + _volumeValue).toStringAsFixed(2));
    if (value >= 1.0) {
      value = 1.0;
    } else if (value <= 0.0) {
      value = 0.0;
    }
    debugPrint('[VideoPlayer] _getVolumeValue() $value');
    return value;
  }

  // 计算播放进度百分比
  double _getSeekValue() {
    // 进度条百分控制
    double valueHorizontal =
        double.parse((_movePan / _width).toStringAsFixed(2));
    // 当前进度条百分比
    double currentValue = _positionValue.inMilliseconds /
        videoPlayerController.value.duration.inMilliseconds;
    double value =
        double.parse((currentValue + valueHorizontal).toStringAsFixed(2));
    if (value >= 1.00) {
      value = 1.00;
    } else if (value <= 0.00) {
      value = 0.00;
    }
    debugPrint('[VideoPlayer] _getSeekValue() $value');
    return value;
  }

  // 重置手势
  void _resetPan() {
    debugPrint('[VideoPlayer] _resetPan()');
    _startPanOffset = const Offset(0, 0);
    _movePan = 0;
    _width = context.size!.width;
    _height = context.size!.height;
  }
}

// ignore: must_be_immutable
class PercentageWidget extends StatefulWidget {
  PercentageWidget({Key? key}) : super(key: key);
  late Function(String) percentageCallback; // 百分比
  late Function(bool) offstageCallback;

  @override
  _PercentageWidgetState createState() => _PercentageWidgetState();
}

class _PercentageWidgetState extends State<PercentageWidget> {
  String _percentage = ""; // 具体的百分比信息
  bool _offstage = true;

  @override
  void initState() {
    super.initState();
    widget.percentageCallback = (percentage) {
      _percentage = percentage;
      _offstage = false;
      if (!mounted) return;
      setState(() {});
    };
    widget.offstageCallback = (offstage) {
      _offstage = offstage;
      if (!mounted) return;
      setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Offstage(
        offstage: _offstage,
        child: Container(
          padding: const EdgeInsets.all(8.0),
          decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.all(Radius.circular(5.0))),
          child: Text(_percentage,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ),
    );
  }
}
