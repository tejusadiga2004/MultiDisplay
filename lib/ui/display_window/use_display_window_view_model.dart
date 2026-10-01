import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../services/app_services.dart';
import '../../services/window_service.dart';
import 'display_window_logic.dart';
import 'display_window_state.dart';

typedef DisplayWindowViewModel = ({
  DisplayWindowState state,
  DisplayWindowLogic actions,
});

DisplayWindowViewModel useDisplayWindowViewModel(
    DisplayWindowSpec spec, int nativeHandle) {
  final BuildContext context = useContext();
  final services = AppServices.of(context);
  final logic = useMemoized(
    () => DisplayWindowLogic(
      api: services.api,
      windows: services.windows,
      spec: spec,
      nativeHandle: nativeHandle,
    ),
    [services.api, services.windows, spec, nativeHandle],
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
