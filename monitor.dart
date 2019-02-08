import 'dart:async';
import 'dart:convert' as c;
import 'dart:io';
import 'package:path/path.dart' show join;

/// monitors lib folder for file changes and restarts server as needed
///
/// the program can be placed in bin directory but it must be run from
/// the projects root directory:
/// ```
/// dart bin/monitor.dart
/// ```
/// Features:
///   * watches lib and all its sub folders and their sub folders...
///   * automatically adds new folder to watch list when its created
///   * automatically removes deleted folder (and sub folder) from watch list
///   * restarts the server only when a file is saved
///   * restarts only once when multiple files are saved concurrently
///   * does not restart when a new empty file is created
/// Quirks:
///   - assumes it is in root directory and server is started with
///     ```
///     dart bin/main/dart
///     ```
///   * does not restart when a file or folder is copied/pasted
///   * does not restart when a file or folder is deleted
void main() {
  // start server first (in background)
  _start();

  // create watcher for lib and all its sub folders recursively
  // use join to accommodate multiple OS platforms
  _add(Directory(join(_root, 'lib')));

  // intercept SIGINT (Ctrl-c) and kill server before exiting
  ProcessSignal.sigint.watch().listen((_) {
    _stop();
    print('\n***** exiting...');
    exit(0);
  });
}

/// minimum time, in milliseconds, between restarts, used to avoid
/// multiple restarts when multiple files are saved together
const int delay = 500;

/// root folder of project - assuming script is run from there
final _root = Directory.current.path;
final _executable = <String>[join(_root, 'bin', 'main.dart')];

/// map of all the folders' watchers
final Map<String, StreamSubscription> _watchers = {};

/// server process
Process _server;

/// last time server was restarted. used to avoid multiple
/// restarts when multiple files are saved together
int _lastRestart = 0;

/// last time a create event occurred. used to avoid a restart when an
/// empty file is created, which triggers a modify event automatically
int _lastCreate = 0;

/// used to display [_server] output messages
StreamSubscription<List<int>> _stdoutSubscription;

/// used to display [_server] error messages
StreamSubscription<List<int>> _stderrSubscription;

/// recursively creates watchers for a folder and all its
/// subdirectories, applies only to [entity] that is a
/// folder and does not already exist in [_watchers] map
void _add(FileSystemEntity entity) {
  // check if entity is an unwatched folder
  // note: using (entity is Directory) did not work
  if (FileSystemEntity.isDirectorySync(entity.path) &&
      _watchers[entity.path] == null) {
    final directory = entity as Directory;
    _watchers[entity.path] = _watcher(directory);
    // print('***** now watching:\n${_watchers.keys}');

    // recursively add all subdirectories
    directory.list(recursive: false, followLinks: false).listen(_add);
  }
}

/// creates a subscription stream that watches a [directory] for changes
StreamSubscription _watcher(Directory directory) =>
    directory.watch().listen((event) {
      // print('***** event:\n$event');
      // print('***** applies to ${event.path}');
      switch (event.type) {
        case FileSystemEvent.create:
          _lastCreate = DateTime.now().millisecondsSinceEpoch;
          _add(Directory(event.path));
          break;
        case FileSystemEvent.modify:
          _start(event.path);
          break;
        case FileSystemEvent.move:
          final move = event as FileSystemMoveEvent;
          _start(move.destination);
          _add(Directory(move.destination));
          break;
        case FileSystemEvent.delete:
          _delete(event.path);
          break;
        default:
      }
    });

/// recursively un-watches folder, referenced by its path [top], and
/// all its sub folders, and removes them from [_watchers] map.
void _delete(String top) {
  // make a list copy of _watchers' keys
  final deleteList = _watchers.keys.toList();
  for (final key in deleteList) {
    // if top or sub folder of it
    if (key.contains(top)) {
      _watchers[key].cancel();
      _watchers.remove(key);
    }
  }
}

/// (re)starts server in background. accepts as optional
/// the [path] to the file that triggered the restart
void _start([String path]) async {
  final now = DateTime.now().millisecondsSinceEpoch;

  // avoid multiple restarts when multiple files are saved together or
  // when empty file is created which automatically triggers a modify event
  if (now - _lastRestart > delay && now - _lastCreate > delay) {
    _lastRestart = now;

    print('*********************************');
    if (path != null) {
      print('file was modified:\n  $path\n');
    }

    // stop running server if needed
    _stop();

    // start server
    print('starting server ...');
    _server = await Process.start('dart', _executable);

    // monitor output messages and write to [stdout]
    _stdoutSubscription = _server.stdout.listen(_output);

    // monitor error messages and write to [stdout]
    _stderrSubscription = _server.stderr.listen(_output);
  }
}

/// stops [_server] if running and cancels any existing stream subscriptions
void _stop() async {
  if (_server != null) {
    print('stopping server ...');

    // cancel subscriptions if needed
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();

    // kill server if running
    _server?.kill();
  }
}

/// sends raw bytes [data] to stdout as characters
void _output(List<int> data) => stdout.write(c.latin1.decode(data));
