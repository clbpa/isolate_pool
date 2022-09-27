part of '../isolate_pool.dart';

Future<IsolatePool> createIsolatePool(String name) {
  final pool = _DartIsolatePool(name);
  return pool._init().then((_) => pool);
}

abstract class IsolatePool {
  String get name;

  int get poolSize;

  int get taskCount;

  Task<R, M> execute<R, M>(Compute<R, M> compute, M message, [String name]);

  Future<void> shutdown();
}

class _DartIsolatePool implements IsolatePool {
  _DartIsolatePool(this.name) : _logger = Logger(name);

  @override
  final String name;
  final Logger _logger;

  final _queue = Queue<Task>();
  final _pool = <_Worker>[];

  @override
  int get poolSize => Platform.numberOfProcessors - 1;

  @override
  int get taskCount => _queue.length;

  Future<void> _init() async {
    assert(_pool.isEmpty, 'Pool $name has been initialized');
    for (var i = 0; i < poolSize; i++) {
      _pool.add(_Worker('worker-$i'));
    }

    _logger.info('Initializing with ${_pool.length} isolate worker...');
    return Future.wait(_pool.map((w) => w.init())).then((_) {
      _logger.info('Initialized!');
    });
  }

  var _taskIdCount = 0;

  @override
  Task<R, M> execute<R, M>(Compute<R, M> compute, M message, [String? name]) {
    final id = _taskIdCount++;
    final task = Task(
      id,
      compute: compute,
      message: message,
      name: name ?? 'task-$id',
    );

    _queue.add(task);
    _logger.info('Added task ${task.name} to queue');

    task._onCancel = () => _cancel(task);
    _schedule();
    return task;
  }

  _Worker? _availableWorker() {
    for (final worker in _pool) {
      if (worker._runningTask == null) {
        return worker;
      }
    }
    return null;
  }

  void _schedule() {
    if (_queue.isEmpty) {
      return;
    }

    final availableWorker = _availableWorker();
    if (availableWorker == null) {
      return;
    }

    final task = _queue.removeFirst();
    task._status = TaskStatus.running;
    _logger.info(
      'Running task ${task.name} on isolate ${availableWorker.name}...',
    );
    availableWorker.work(task).then((result) {
      task._result.complete(result);
    }).catchError((e, s) {
      task._result.completeError(e, s);
    }).whenComplete(() {
      task._status = TaskStatus.finished;
      _logger.info('Task ${task.name} completed!');
      _logger.info('Isolate ${availableWorker.name} is available!');
      _schedule();
    });
  }

  _Worker? _currentWorker(int id) {
    for (final worker in _pool) {
      if (worker._runningTask?.id == id) {
        return worker;
      }
    }
    return null;
  }

  void _cancel(Task task) {
    task._status = TaskStatus.cancelled;
    if (_queue.contains(task)) {
      _queue.remove(task);
      _logger.info('Task ${task.name} removed from queue');
      return;
    }

    final worker = _currentWorker(task.id);
    if (worker == null) {
      return;
    }

    worker.kill().then((_) {
      worker.init().then((_) => _schedule());
    }).whenComplete(() {
      _logger.info('Task ${task.name} cancelled');
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
