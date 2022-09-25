part of '../isolate_pool.dart';

Future<IsolatePool> createIsolatePool(String name) {
  final pool = _DartIsolatePool(name);
  return pool.init().then((_) => pool);
}

final _logger = Logger('isolate-pool');

abstract class IsolatePool {
  String get name;

  int get poolSize;

  int get taskCount;

  void execute(Task task);

  Future<void> shutdown();
}

class _DartIsolatePool implements IsolatePool {
  _DartIsolatePool(this.name);

  @override
  final String name;

  final _queue = Queue<Task>();
  final _pool = <_Worker>[];

  @override
  int get poolSize => Platform.numberOfProcessors;

  @override
  int get taskCount => _queue.length;

  Future<void> init() async {
    assert(_pool.isEmpty, 'Pool has been initialized');
    for (var i = 0; i < poolSize; i++) {
      _pool.add(_Worker('worker-$i'));
    }

    _logger.info('Initializing with ${_pool.length} isolate worker...');
    return Future.wait(_pool.map((w) => w.init())).then((_) {
      _logger.info('Initialized!');
    });
  }

  @override
  void execute(Task task) {
    _queue.add(task);
    _logger.info('Added task ${task.id} to queue');
    task._status = TaskStatus.running;
    task._onCancel = () => _cancel(task);
    _schedule();
  }

  void _schedule() {
    if (_queue.isEmpty) {
      return;
    }

    final availableWorker =
        _pool.firstWhereOrNull((w) => w.runningTask == null);
    if (availableWorker == null) {
      return;
    }

    final task = _queue.removeFirst();
    _logger.info(
      'Running task ${task.id} on isolate ${availableWorker.name}...',
    );
    task._status = TaskStatus.running;
    availableWorker.work(task).then((result) {
      task._result.complete(result);
    }).catchError((e, s) {
      task._result.completeError(e, s);
    }).whenComplete(() {
      task._status = TaskStatus.finished;
      _logger.info('Task ${task.id} completed!');
      _logger.info('Isolate ${availableWorker.name} is available!');
      _schedule();
    });
  }

  void _cancel(Task task) {
    task._status = TaskStatus.cancelled;
    if (_queue.contains(task)) {
      _queue.remove(task);
      _logger.info('Task ${task.id} removed from queue');
      return;
    }

    final worker = _pool.firstWhereOrNull((w) => w.runningTask == task.id);
    if (worker == null) {
      return;
    }

    worker.kill().then((_) {
      worker.init().then((_) => _schedule());
    }).whenComplete(() {
      _logger.info('Task ${task.id} cancelled');
      _logger.info('Isolate ${worker.name} respawned');
    });
  }

  @override
  Future<void> shutdown() async {
    _queue.clear();
    await Future.wait(_pool.map((e) => e.kill()));
    _pool.clear();
  }
}
