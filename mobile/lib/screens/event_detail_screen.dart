import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import '../utils.dart';
import 'checkout_screen.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId, this.initialEvent});

  final String eventId;
  final Event? initialEvent;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _nameController = TextEditingController();
  final Map<String, int> _quantities = {};
  Event? _event;
  bool _loading = true;
  bool _booking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _nameController.text = context.read<AuthState>().user?.fullName ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final event = await context.read<AuthState>().api.getEvent(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = event;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  int get _totalTickets =>
      _quantities.values.fold(0, (sum, quantity) => sum + quantity);

  int get _totalMinor {
    final event = _event;
    if (event == null) return 0;
    var total = 0;
    for (final type in event.ticketTypes) {
      total += (_quantities[type.id] ?? 0) * type.priceMinor;
    }
    return total;
  }

  void _changeQuantity(TicketType type, int delta) {
    final current = _quantities[type.id] ?? 0;
    final next = current + delta;
    if (next < 0) return;
    if (next > type.remaining) return;
    if (delta > 0 && _totalTickets >= 20) return;
    setState(() {
      if (next == 0) {
        _quantities.remove(type.id);
      } else {
        _quantities[type.id] = next;
      }
    });
  }

  Future<void> _reserve() async {
    final event = _event;
    if (event == null || _totalTickets == 0) return;
    setState(() => _booking = true);

    try {
      final booking = await context.read<AuthState>().api.createBooking(
            eventId: event.id,
            idempotencyKey: newIdempotencyKey(),
            attendeeName: _nameController.text,
            items: _quantities.entries
                .map((entry) => {
                      'ticket_type_id': entry.key,
                      'quantity': entry.value,
                    })
                .toList(),
          );
      if (!mounted) return;
      setState(() {
        _booking = false;
        _quantities.clear();
      });
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CheckoutScreen(bookingId: booking.id)),
      );
      if (mounted) _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _booking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      if (error.code == 'SOLD_OUT') _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = _event;

    return Scaffold(
      appBar: AppBar(title: Text(event?.title ?? 'Event')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : event == null
                  ? const Center(child: Text('Event not found'))
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _Hero(event: event)),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 160),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              Row(
                                children: [
                                  _InfoPill(
                                    icon: Icons.calendar_month_outlined,
                                    label: formatEventDate(event.startsAt),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _InfoPill(
                                    icon: Icons.place_outlined,
                                    label: event.venue,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'About this event',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                event.description.isEmpty
                                    ? 'More details coming soon.'
                                    : event.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Organised by ${event.organizerName}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Choose tickets',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (event.ticketTypes.isEmpty)
                                const Text('Tickets are not on sale yet.')
                              else
                                ...event.ticketTypes.map(
                                  (type) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _TicketTypeTile(
                                      type: type,
                                      quantity: _quantities[type.id] ?? 0,
                                      onAdd: () => _changeQuantity(type, 1),
                                      onRemove: () => _changeQuantity(type, -1),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Attendee name on tickets',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ),
      bottomNavigationBar: event == null || _loading || _error != null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            formatMoney(_totalMinor),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 190,
                      child: FilledButton(
                        onPressed: _booking || _totalTickets == 0
                            ? null
                            : _reserve,
                        child: _booking
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _totalTickets == 0
                                    ? 'Select tickets'
                                    : 'Reserve $_totalTickets',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              event.remaining <= 0 ? 'SOLD OUT' : '${event.remaining} TICKETS LEFT',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            event.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            formatEventDate(event.startsAt),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketTypeTile extends StatelessWidget {
  const _TicketTypeTile({
    required this.type,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final TicketType type;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soldOut = type.isSoldOut;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: quantity > 0
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: quantity > 0 ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  soldOut ? 'Sold out' : '${type.remaining} available',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: soldOut
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  formatMoney(type.priceMinor, type.currency),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          _QuantityControl(
            quantity: quantity,
            enabled: !soldOut,
            onAdd: onAdd,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: quantity == 0 ? null : onRemove,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? onAdd : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
