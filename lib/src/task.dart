part of '../isolate_pool.dart';

enum TaskStatus { waiting, running, finished, cancelled }

class Task<T, M> {
  Task(
    this.id, {
    required Compute<T, M> compute,
    required M message,
    required this.name,
  }) : _runnable = _Runnable(compute, message);

  final int id;
  final _Runnable<T, M> _runnable;
  final String name;
  TaskStatus _status = TaskStatus.waiting;

  final StreamController<dynamic> _updateController =
      StreamController.broadcast(sync: true);
  final Completer<T> _result = Completer();

  Stream<dynamic> get onUpdate => _updateController.stream;

  Future<T> get result => _result.future;

  TaskStatus get status => _status;

  bool get waiting => _status == TaskStatus.waiting;

  bool get running => _status == TaskStatus.running;

  bool get finished => _status == TaskStatus.finished;

  bool get cancelled => _status == TaskStatus.cancelled;

  late Function() _onCancel;

  void cancel() {
    assert(running, "Task $name is not running");
    _onCancel();
  }

  Future<void> dispose() {
    assert(!_updateController.isClosed);
    return _updateController.close();
  }
}
