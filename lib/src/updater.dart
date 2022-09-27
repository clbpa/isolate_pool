part of '../isolate_pool.dart';

class Updater {
  Updater(this._sendPort);

  final SendPort _sendPort;

  void update(dynamic data) => _sendPort.send(data);
}
