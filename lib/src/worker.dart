part of '../isolate_pool.dart';

class _Worker {
  _Worker(this.name);

  final String name;

  late Isolate _isolate;
  late RawReceivePort _receivePort;
  late SendPort _sendPort;

  late Completer<dynamic> _result;

  String? _runningTask;

  String? get runningTask => _runningTask;

  Future<void> init() async {
    final initCompleter = Completer();
    _receivePort = RawReceivePort((message) {
      if (message is ValueResult) {
        _result.complete(message.value);
        _runningTask = null;
        return;
      }
      if (message is ErrorResult) {
        _result.completeError(message.error);
        _runningTask = null;
        return;
      }
      if (message is SendPort) {
        _sendPort = message;
        initCompleter.complete(true);
      }
    }, '$name-receive-port');
    _isolate = await Isolate.spawn(
      _spawn,
      _receivePort.sendPort,
      debugName: '$name-isolate',
    );
    await initCompleter.future;
  }

  Future<T> work<T>(Task<T> task) async {
    _runningTask = task.id;
    _result = Completer();
    _sendPort.send(_IsolateCallRequest(
      task.compute,
      task._progress,
      task.context,
    ));
    final result = await _result.future;
    return result;
  }

  Future<void> kill() async {
    _runningTask = null;
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _IsolateCallRequest {
  _IsolateCallRequest(this.compute, this.progress, [this.context]);

  final FutureOr Function(StreamSink progress, [TaskContext? context]) compute;
  final StreamSink progress;
  final TaskContext? context;
}

void _spawn(SendPort sendPort) {
  final receivePort = RawReceivePort((request) async {
    request as _IsolateCallRequest;
    try {
      final computed = await request.compute.call(
        request.progress,
        request.context,
      );
      sendPort.send(Result.value(computed));
    } catch (error, stackTrace) {
      try {
        sendPort.send(Result.error(error, stackTrace));
      } catch (error) {
        sendPort.send(Result.error(
          'cant send error with too big stackTrace, error is : ${error.toString()}',
        ));
      }
    }
  });
  sendPort.send(receivePort.sendPort);
}
