/// Pure list math for maintaining the shuffle order when items are appended
/// to the play queue.
///
/// The played prefix — everything up to and including the track at
/// [currentIndex] — is preserved in place, so the id of the track playing right
/// now keeps its slot and [currentIndex] stays valid. Only the not-yet-played
/// tail is re-shuffled together with [newIds].
List<String> appendToShuffleOrder(
    List<String> order, int currentIndex, List<String> newIds) {
  if (order.isEmpty) {
    return [...newIds]..shuffle();
  }
  final head = currentIndex.clamp(0, order.length - 1);
  final tail = order.sublist(head + 1)
    ..addAll(newIds)
    ..shuffle();
  return [...order.take(head + 1), ...tail];
}
