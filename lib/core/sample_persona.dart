import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which sample player debug builds show (Settings › Developer), so both the
/// seasoned and the first-time experience can be checked on a device.
/// Release builds never use sample data.
enum SamplePersona {
  regular('Regular player', 'Matches, a live tournament, a rating'),
  newcomer('New player', 'Nothing yet: every empty state');

  const SamplePersona(this.label, this.description);
  final String label;
  final String description;
}

final samplePersonaProvider = NotifierProvider<SamplePersonaController, SamplePersona>(SamplePersonaController.new);

class SamplePersonaController extends Notifier<SamplePersona> {
  @override
  SamplePersona build() => SamplePersona.regular;

  void set(SamplePersona persona) => state = persona;
}
