import 'package:domain/domain.dart';

import 'app_store.dart';
import 'snackbar_state.dart';

/// The actions a credit row and the credit sheet offer, with their feedback
/// attached.
///
/// Every list that renders a row shares this so a swipe behaves identically
/// to the same action taken from the sheet. It also guarantees the part that
/// matters: a swipe is easy to trigger by accident, so logging one always
/// returns an undo rather than silently altering a balance.
class CreditActions {
  const CreditActions({required this.store, required this.snackbar});

  final AppStore store;
  final SnackbarState snackbar;

  /// Logs a use, the whole remaining balance unless [amountCents] says
  /// otherwise, with an undo that removes exactly that claim.
  Future<Claim> log(BenefitInstance instance, {int? amountCents}) async {
    final claim = await store.claim(instance, amountCents: amountCents);
    final name = instance.benefit.name;
    snackbar.show(
      'Logged ${formatMoney(claim.amountCents)} on $name.',
      action: SnackbarAction(
        label: 'Undo',
        semanticsLabel: 'Undo logging $name',
        onAct: () => store.removeClaim(claim.id),
      ),
    );
    return claim;
  }

  /// Logs the whole remaining balance, with an undo.
  Future<Claim> logAll(BenefitInstance instance) => log(instance);

  /// Silences or unsilences one credit, with an undo.
  Future<void> toggleMute(BenefitInstance instance) async {
    final wasMuted = instance.benefit.muted;
    final id = instance.benefit.id;
    final name = instance.benefit.name;
    await store.toggleBenefitMute(id);
    snackbar.show(
      wasMuted
          ? 'Reminders back on for $name.'
          : 'Silenced $name. It is still tracked.',
      action: SnackbarAction(
        label: 'Undo',
        semanticsLabel: wasMuted
            ? 'Undo reminders back on for $name'
            : 'Undo silencing $name',
        onAct: () => store.toggleBenefitMute(id),
      ),
    );
  }

  /// Records the issuer's enrolment box as ticked, with an undo.
  Future<void> confirmEnrollment(BenefitInstance instance) async {
    final id = instance.benefit.id;
    final name = instance.benefit.name;
    await store.confirmEnrollment(id);
    snackbar.show(
      '$name unlocked.',
      action: SnackbarAction(
        label: 'Undo',
        semanticsLabel: 'Undo unlocking $name',
        onAct: () => store.revokeEnrollment(id),
      ),
    );
  }

  /// Records this year's spend threshold as reached, with an undo.
  Future<void> confirmSpend(BenefitInstance instance) async {
    final id = instance.benefit.id;
    final name = instance.benefit.name;
    await store.confirmSpend(id);
    snackbar.show(
      '$name unlocked.',
      action: SnackbarAction(
        label: 'Undo',
        semanticsLabel: 'Undo unlocking $name',
        onAct: () => store.revokeSpend(id),
      ),
    );
  }

  /// Removes one claim. No undo: the sheet is the way back for a claim, and
  /// what was removed is said.
  Future<void> removeClaim(BenefitInstance instance, Claim claim) async {
    await store.removeClaim(claim.id);
    snackbar.show(
      'Removed ${formatMoney(claim.amountCents)} from ${instance.benefit.name}.',
    );
  }

  /// Clears every claim on the cycle.
  Future<void> unclaimAll(BenefitInstance instance) async {
    await store.unclaim(instance.benefit.id, instance.cycle.key);
    snackbar.show('Cleared what was logged against ${instance.benefit.name}.');
  }
}
