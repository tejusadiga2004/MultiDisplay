import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../services/app_services.dart';
import 'display_controller_logic.dart';
import 'display_controller_state.dart';

typedef DisplayControllerViewModel = ({
  DisplayControllerState state,
  DisplayControllerLogic actions,
});

/// Creates the logic, runs init/dispose with the widget lifecycle and returns
/// the current state plus the actions (SPEC §9.0).
DisplayControllerViewModel useDisplayControllerViewModel() {
  final BuildContext context = useContext();
  final services = AppServices.of(context);
  final logic = useMemoized(
    () => DisplayControllerLogic(
      api: services.api,
      windows: services.windows,
      settings: services.settings,
    ),
    [services.api, services.windows, services.settings],
  );
  useEffect(() {
    logic.init();
    return () {
      logic.dispose();
    };
  }, [logic]);
  final state = useValueListenable(logic.state);
  return (state: state, actions: logic);
}
