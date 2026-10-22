import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../ticket_cache.dart';
import 'checkout_screen.dart';

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  Booking? _booking;
  bool _loading = true;
  bool _offline = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthState>();
    final userId = auth.user?.id ?? 'guest';
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking = await auth.api.getBooking(widget.bookingId);
      final cached = await TicketCache.load(userId);
      final merged = [
        booking,
        ...cached.where((item) => item.id != booking.id),
      ];
      await TicketCache.save(userId, merged);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
        _offline = false;
      });
    } on ApiException catch (error) {
      final cached = await TicketCache.load(userId);
      final booking = cached.where((item) => item.id == widget.bookingId).firstOrNull;
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
        _offline = booking != null;
        _error = booking == null ? error.message : null;
      });
    }
  }

  Future<void> _cancel() async {
    final booking = _booking;
    if (booking == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text(
          'The tickets will stop working and the seats will be released.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;

    try {
      final cancelled = await context.read<AuthState>().api.cancelBooking(booking.id);
      if (!mounted) return;
      setState(() => _booking = cancelled);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final booking = _booking;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your tickets'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : booking == null
                  ? const Center(child: Text('Booking not found'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        if (_offline) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.wifi_off, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Offline: this ticket was loaded from secure local storage.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  booking.event.title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${formatEventDate(booking.event.startsAt)} · ${booking.event.venue}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        booking.statusLabel,
                                        style: TextStyle(
                                          color: theme.colorScheme.onPrimaryContainer,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      formatMoney(booking.totalMinor, booking.currency),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (booking.isPending)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Icon(Icons.timer_outlined, size: 32),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Payment not completed yet',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Your seats are held until '
                                    '${booking.expiresAt == null ? 'the hold expires' : formatEventDate(booking.expiresAt)}.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              CheckoutScreen(bookingId: booking.id),
                                        ),
                                      );
                                      if (mounted) _load();
                                    },
                                    child: const Text('Complete payment'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (booking.isConfirmed)
                          ...booking.tickets.map(
                            (ticket) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _TicketCard(ticket: ticket, booking: booking),
                            ),
                          )
                        else
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.event_busy,
                                    size: 42,
                                    color: theme.colorScheme.error,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'This booking is ${booking.statusLabel.toLowerCase()}.',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'The QR codes for these tickets no longer work.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (booking.isConfirmed || booking.isPending) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _cancel,
                            icon: Icon(Icons.close, color: theme.colorScheme.error),
                            label: Text(
                              'Cancel booking',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ],
                    ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.booking});

  final Ticket ticket;
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = ticket.isUsed;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.ticketTypeName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ticket.attendeeName ?? 'EventFlow attendee',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: used
                        ? Colors.black.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    used ? 'USED' : 'VALID',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (used)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Checked in${ticket.usedAt == null ? '' : ' ${formatEventDate(ticket.usedAt)}'}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                QrImageView(
                  data: ticket.token,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF111111),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF111111),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Short code',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ticket.shortCode,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Show this QR code at the entrance. Staff can also enter the short code if your camera or data is unavailable.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
