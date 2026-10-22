import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../ticket_cache.dart';
import 'booking_detail_screen.dart';
import 'checkout_screen.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<Booking> _bookings = [];
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
      _loading = _bookings.isEmpty;
      _error = null;
    });

    try {
      final bookings = await auth.api.getBookings();
      await TicketCache.save(userId, bookings);
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
        _offline = false;
      });
    } on ApiException catch (error) {
      final cached = await TicketCache.load(userId);
      if (!mounted) return;
      setState(() {
        _bookings = cached;
        _loading = false;
        _offline = cached.isNotEmpty;
        _error = cached.isEmpty ? error.message : null;
      });
    }
  }

  Future<void> _open(Booking booking) async {
    if (booking.isPending) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CheckoutScreen(bookingId: booking.id)),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: booking.id)),
      );
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _bookings.where((booking) => !booking.isCancelled).toList();
    final past = _bookings.where((booking) => booking.isCancelled).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My tickets'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      Icon(Icons.cloud_off, size: 52, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (_offline)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
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
                                  'Offline mode: showing tickets saved on this phone.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_bookings.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 100),
                          child: Column(
                            children: [
                              Icon(
                                Icons.confirmation_number_outlined,
                                size: 56,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No tickets yet.\nHead to Discover and book your first event.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (active.isNotEmpty) ...[
                        Text(
                          'Current',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...active.map(
                          (booking) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BookingCard(
                              booking: booking,
                              onTap: () => _open(booking),
                            ),
                          ),
                        ),
                      ],
                      if (past.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Past and cancelled',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...past.map(
                          (booking) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BookingCard(
                              booking: booking,
                              onTap: () => _open(booking),
                              muted: true,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.onTap,
    this.muted = false,
  });

  final Booking booking;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = booking.isConfirmed
        ? theme.colorScheme.primary
        : booking.isPending
            ? Colors.orange.shade800
            : theme.colorScheme.outline;

    return Opacity(
      opacity: muted ? 0.7 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 62,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.confirmation_number_outlined, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatEventDate(booking.event.startsAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              booking.statusLabel,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${booking.tickets.length} ticket${booking.tickets.length == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
