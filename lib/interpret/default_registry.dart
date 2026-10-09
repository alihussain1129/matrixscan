import 'contact_interpreter.dart';
import 'emv_interpreter.dart';
import 'gs1_interpreter.dart';
import 'interpreter.dart';
import 'url_interpreter.dart';
import 'wifi_interpreter.dart';

/// The interpreters EXALTED ships with, in the order they are tried.
InterpreterRegistry defaultInterpreterRegistry({DateTime Function()? clock}) =>
    InterpreterRegistry([
      WifiInterpreter(),
      ContactInterpreter(),
      EmvInterpreter(),
      Gs1Interpreter(clock: clock),
      UrlInterpreter(),
    ]);