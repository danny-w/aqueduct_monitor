# aqueduct_monitor
monitor dart aqueduct project for file changes and automatically restart the server

the program can be placed in bin directory but it must be run from the projects root directory:
```
dart bin/monitor.dart
```
## Features:
  * watches lib and all its sub folders and their sub folders...
  * automatically adds new folder to watch list when its created
  * automatically removes deleted folder (and sub folder) from watch list
  * restarts the server only when a file is saved
  * restarts only once when multiple files are saved concurrently
  * does not restart when a new empty file is created
## Quirks:
  * tested only on Ubuntu 18.04 system.
  * assumes it is in root directory and server is started with
    ```
    dart bin/main/dart
    ```
  * does not restart when a file or folder is copied/pasted
  * does not restart when a file or folder is deleted
