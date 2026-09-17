import '../test/body_coverage_test.dart' as bodies;
import '../test/gameplay_regression_test.dart' as gameplay;
import '../test/core_test.dart' as core;
import '../test/recovery_test.dart' as recovery;
import '../test/palette_test.dart' as palette;
import '../test/locomotion_test.dart' as locomotion;
import '../test/movement_input_test.dart' as input;
import '../test/workspace_interaction_test.dart' as workspace;

void main() {
  bodies.main();
  core.main();
  recovery.main();
  palette.main();
  locomotion.main();
  input.main();
  workspace.main();
  gameplay.main();
}
