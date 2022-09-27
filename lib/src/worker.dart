part of '../isolate_pool.dart';

class _Worker {
  _Worker(this.name);

  final String name;

  late Isolate _isolate;
  late RawReceivePort _receivePort;
  late SendPort _sendPort;

  late Completer<List<dynamic>> _result;

  Task<dynamic, dynamic>? _runningTask;

  Future<void> init() async {
    final initCompleter = Completer();
    _receivePort = RawReceivePort(
      (message) {
        if (message is List<dynamic>) {
          _result.complete(message);
          _runningTask = null;
          return;
        }

        if (message is SendPort) {
          _sendPort = message;
          initCompleter.complete(true);
          return;
        }

        _runningTask?._updateController.add(message);
      },
      '$name-receive-port',
    );
    _isolate = await Isolate.spawn(
      _spawn,
      _receivePort.sendPort,
      debugName: '$name-isolate',
    );

    await initCompleter.future;
  }

  Future<T> work<T>(Task<T, dynamic> task) async {
    _runningTask = task;
    _result = Completer<List<dynamic>>();
    _sendPort.send(_IsolateCallRequest(_execute, task._runnable));

    final response = await _result.future;

    final int type = response.length;
    assert(1 <= type && type <= 3);

    switch (type) {
      // success; see _buildSuccessResponse
      case 1:
        return response[0] as T;

      // native error; see Isolate.addErrorListener
      case 2:
        await Future<Never>.error(RemoteError(
          response[0] as String,
          response[1] as String,
        ));

      // caught error; see _buildErrorResponse
      case 3:
      default:
        assert(type == 3 && response[2] == null);

        await Future<Never>.error(
          response[0] as Object,
          response[1] as StackTrace,
        );
    }
  }

  Future<void> kill() async {
    _runningTask = null;
    _isolate.kill(priority: Isolate.immediate);
  }
}

FutureOr<dynamic> _execute(_Runnable<dynamic, dynamic> runnable) => runnable();

class _IsolateCallRequest {
  _IsolateCallRequest(this.function, this.argument);

  final FutureOr<dynamic> Function(_Runnable<dynamic, dynamic>) function;
  final _Runnable<dynamic, dynamic> argument;
}

void _spawn(SendPort sendPort) {
  final receivePort = RawReceivePort((_IsolateCallRequest request) async {
    late final List<dynamic> computationResult;

    try {
      request.argument.updater = Updater(sendPort);
      computationResult =
          _buildSuccessResponse(await request.function(request.argument));
    } catch (error, stackTrace) {
      computationResult = _buildErrorResponse(error, stackTrace);
    }

    sendPort.send(computationResult);
  });
  sendPort.send(receivePort.sendPort);
}

List<dynamic> _buildSuccessResponse(dynamic result) => List.filled(1, result);

List<dynamic> _buildErrorResponse(Object error, StackTrace stack) =>
    List.filled(3, null)
      ..[0] = error
      ..[1] = stack;
