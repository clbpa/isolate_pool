part of '../isolate_pool.dart';

enum TaskStatus { ready, running, cancelled, finished }

abstract class TaskContext {
  const TaskContext();
}

abstract class Task<T> {
  Task(this.id);

  final String id;

  TaskContext? get context => null;

  FutureOr<T> compute(StreamSink progress, TaskContext? context);

  final StreamController _progress = StreamController.broadcast(sync: true);
  final Completer<T> _result = Completer();

  Stream get onProgress => _progress.stream;

  Future<T> get result => _result.future;

  TaskStatus _status = TaskStatus.ready;

  TaskStatus get status => _status;

  late Function() _onCancel;

  void cancel() {
    assert(_status == TaskStatus.running, "Task $id is not running");
    _onCancel.call();
  }
}
