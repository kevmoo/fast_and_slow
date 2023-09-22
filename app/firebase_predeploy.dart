#!/usr/bin/env dart
// ignore_for_file: avoid_print

import 'dart:io';

enum WebBuildMode {
  jsHtml(wasmCompile: false, renderer: 'html'),
  jsCanvas(wasmCompile: false, renderer: 'canvaskit'),
  wasm(wasmCompile: true, renderer: 'canvaskit'),
  skwasm(wasmCompile: true, renderer: 'skwasm');

  const WebBuildMode({required this.wasmCompile, required this.renderer});

  final bool wasmCompile;
  final String renderer;

  List<String> get args => [
        if (wasmCompile) '--wasm',
        '--web-renderer',
        renderer,
      ];
}

Future<void> main(List<String> args) async {
  final explicitMode = Platform.environment['build_mode'];

  print('Explicit `build_mode`: "$explicitMode"');

  final mode = WebBuildMode.jsCanvas;

  print('using mode "${mode.name}"');

  await _runFlutter(
    [
      'build',
      'web',
      '--pwa-strategy',
      'none',
      '--verbose',
      ...mode.args,
    ],
    getOutput: false,
  );
}

Future<String> _runFlutter(List<String> args, {required bool getOutput}) =>
    _runCommand('flutter', args, getOutput: getOutput);

Future<String> _runCommand(String processName, List<String> args,
    {required bool getOutput}) async {
  print(['RUNNING:', processName, ...args].join(' '));

  final proc = await Process.start(
    processName,
    args,
    mode: getOutput ? ProcessStartMode.normal : ProcessStartMode.inheritStdio,
    runInShell: true,
  );

  final stderrBuffer = StringBuffer();
  final stdoutBuffer = StringBuffer();

  late int procExit;

  await Future.wait([
    proc.exitCode.then((value) {
      procExit = value;
    }),
    if (getOutput) ...[
      proc.stderr
          .transform(const SystemEncoding().decoder)
          .forEach(stderrBuffer.write),
      proc.stdout
          .transform(const SystemEncoding().decoder)
          .forEach(stdoutBuffer.write),
    ]
  ]);

  if (procExit != 0) {
    throw ProcessException(
        processName, args, stderrBuffer.toString(), procExit);
  }

  return stdoutBuffer.toString();
}
