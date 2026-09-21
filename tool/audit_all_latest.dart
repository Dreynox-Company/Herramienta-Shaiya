import 'dart:async';
import 'dart:io';
import 'run_all_local.dart' as regression;

void main() {
  runZonedGuarded(
    regression.main,
    (e, s) {
      stderr.writeln('$e\n$s');
      exit(1);
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        if (line.contains('All tests passed!')) {
          Timer(const Duration(milliseconds: 50), () => exit(0));
        }
        if (line.contains('Some tests failed.')) {
          Timer(const Duration(milliseconds: 50), () => exit(1));
        }
      },
    ),
  );
}
