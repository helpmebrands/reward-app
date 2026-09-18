import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';

import '../data/snapshot_store.dart';

/// The app store: the one `AppData` snapshot, today's date, and the derived
/// views the screens read. Mutations write the snapshot back through the
/// [SnapshotStore]; screens never touch storage.
class AppStore extends ChangeNotifier {
  AppStore({required SnapshotStore store, IsoDate Function()? clock})
    // ignore: prefer_initializing_formals
    : _store = store,
      _clock = clock ?? todayIso;

  final SnapshotStore _store;
  final IsoDate Function() _clock;

  AppData? _data;
  bool _loading = true;

  /// The snapshot, or null before [load] completes or on a fresh install.
  AppData? get data => _data;
  bool get loading => _loading;

  /// The user's local calendar date. Re-read on every access so an app
  /// resumed the next morning shows that morning's deadlines.
  IsoDate get today => _clock();

  Future<void> load() async {
    _data = await _store.load();
    _loading = false;
    notifyListeners();
  }

  /// Replaces the whole snapshot, as an import does.
  Future<void> replaceAll(AppData data) async {
    _data = data;
    _loading = false;
    await _store.save(data);
    notifyListeners();
  }

  /// Every active credit resolved against today, narrowed by the household
  /// filter, by urgency.
  List<BenefitInstance> get instances {
    final data = _data;
    if (data == null) return const [];
    final all = currentInstances(data, today);
    final holder = data.settings.holderFilter;
    return holder.isEmpty
        ? all
        : all.where((i) => i.card.holder == holder).toList();
  }

  List<MissedCycle> get missed {
    final data = _data;
    return data == null ? const [] : missedCycles(data, today);
  }

  Totals get totals =>
      totalsFor(instances, missed.fold(0, (sum, m) => sum + m.missedCents));

  List<BenefitInstance> get soon => byStatus(instances, BenefitStatus.useSoon);
  List<BenefitInstance> get locked => byStatus(instances, BenefitStatus.locked);
  List<BenefitInstance> get captured =>
      instances.where((i) => i.claimedCents > 0).toList();
  List<OverlapGroup> get overlaps => findOverlaps(instances);
  IsoDate? get nextResetOn => nextReset(instances);
  bool get hasCards => _data?.cards.any((card) => !card.archived) ?? false;
  int get cardCount => _data?.cards.where((card) => !card.archived).length ?? 0;
}
