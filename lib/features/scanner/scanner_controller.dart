import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UI state of the scanner: flash, single or continuous mode, auto scan.
class ScannerUiState {
  const ScannerUiState({
    this.flashOn = false,
    this.continuous = false,
    this.autoScan = true,
  });

  final bool flashOn;
  final bool continuous;
  final bool autoScan;

  ScannerUiState copyWith({bool? flashOn, bool? continuous, bool? autoScan}) {
    return ScannerUiState(
      flashOn: flashOn ?? this.flashOn,
      continuous: continuous ?? this.continuous,
      autoScan: autoScan ?? this.autoScan,
    );
  }
}

class ScannerController extends Notifier<ScannerUiState> {
  @override
  ScannerUiState build() => const ScannerUiState();

  void toggleFlash() => state = state.copyWith(flashOn: !state.flashOn);

  void toggleContinuous() =>
      state = state.copyWith(continuous: !state.continuous);

  void toggleAuto() => state = state.copyWith(autoScan: !state.autoScan);
}

final scannerControllerProvider =
    NotifierProvider<ScannerController, ScannerUiState>(ScannerController.new);