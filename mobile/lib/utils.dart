import 'dart:math';

final Random _random = Random.secure();

String newIdempotencyKey() {
  return 'bk-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}

String prettyStatus(String status) {
  switch (status) {
    case 'published':
      return 'On sale';
    case 'draft':
      return 'Draft';
    case 'cancelled':
      return 'Cancelled';
    case 'confirmed':
      return 'Confirmed';
    case 'pending':
      return 'Pending';
    case 'expired':
      return 'Expired';
    case 'used':
      return 'Checked in';
    case 'valid':
      return 'Valid';
    default:
      return status.isEmpty ? 'Unknown' : status[0].toUpperCase() + status.substring(1);
  }
}
