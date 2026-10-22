import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../auth_state.dart';
import '../models.dart';
import 'booking_detail_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _phoneController = TextEditingController();
  Booking? _booking;
  bool _loading = true;
  bool _paying = false;
  String? _error;
  String _network = 'MTN';
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _phoneController.text = context.read<AuthState>().user?.phone ?? '';
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  void _tick() {
    final expiresAt = _booking?.expiresAt;
    if (!mounted || expiresAt == null || _booking?.isPending != true) return;
    final remaining = expiresAt.difference(DateTime.now());
    setState(() => _remaining = remaining.isNegative ? Duration.zero : remaining);
  }

  Future<void> _load() async {
    try {
      final booking = await context.read<AuthState>().api.getBooking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
        _error = null;
        _tick();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _pay() async {
    final booking = _booking;
    if (booking == null) return;
    if (_phoneController.text.trim().length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the mobile money phone number')),
      );
      return;
    }

    setState(() => _paying = true);
    try {
      final result = await context.read<AuthState>().api.initiatePayment(
            booking.id,
            phone: _phoneController.text,
            network: _network,
          );
      final payment = Payment.fromJson(result['payment'] as Map<String, dynamic>);
      if (!mounted) return;
      setState(() => _paying = false);

      final approved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _PaymentSheet(
          payment: payment,
          phone: _phoneController.text,
          network: _network,
        ),
      );
      if (approved != true || !mounted) return;

      setState(() => _paying = true);
      final confirmed = await context
          .read<AuthState>()
          .api
          .simulatePayment(payment.providerReference);
      if (!mounted) return;
      setState(() {
        _booking = confirmed;
        _paying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment approved. Your tickets are ready.')),
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: confirmed.id),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _paying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      _load();
    }
  }

  Future<void> _cancel() async {
    final booking = _booking;
    if (booking == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: const Text('The held tickets will be released back for other attendees.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final cancelled = await context.read<AuthState>().api.cancelBooking(booking.id);
      if (!mounted) return;
      setState(() => _booking = cancelled);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled and capacity released.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final booking = _booking;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : booking == null
                  ? const Center(child: Text('Booking not found'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _StatusBanner(booking: booking, remaining: _remaining),
                        const SizedBox(height: 16),
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
                                const SizedBox(height: 4),
                                Text(
                                  '${formatEventDate(booking.event.startsAt)} · ${booking.event.venue}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const Divider(height: 28),
                                ...booking.items.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${item.quantity} × ${item.ticketTypeName}',
                                          ),
                                        ),
                                        Text(
                                          formatMoney(
                                            item.quantity * item.unitPriceMinor,
                                            booking.currency,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Divider(height: 28),
                                Row(
                                  children: [
                                    Text(
                                      'Total',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      formatMoney(booking.totalMinor, booking.currency),
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (booking.isConfirmed)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green),
                                      SizedBox(width: 10),
                                      Text(
                                        'Payment confirmed',
                                        style: TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Your tickets are ready. Open them from the Tickets tab.',
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    onPressed: () => Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (_) => BookingDetailScreen(
                                          bookingId: booking.id,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.qr_code_2),
                                    label: const Text('View QR tickets'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (booking.isCancelled)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                'This booking is ${booking.statusLabel.toLowerCase()}. '
                                'The tickets have been released.',
                                style: TextStyle(color: theme.colorScheme.error),
                              ),
                            ),
                          )
                        else ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone_android,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Mobile money',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          'SIMULATED',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: theme.colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'This demo uses a simulated provider. The flow matches '
                                    'an MTN, Airtel or Zamtel mobile money prompt.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'Phone number',
                                      prefixIcon: Icon(Icons.phone_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: _network,
                                    decoration: const InputDecoration(
                                      labelText: 'Network',
                                      prefixIcon: Icon(Icons.cell_tower_outlined),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'MTN', child: Text('MTN')),
                                      DropdownMenuItem(
                                        value: 'AIRTEL',
                                        child: Text('Airtel'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'ZAMTEL',
                                        child: Text('Zamtel'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) setState(() => _network = value);
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                  FilledButton.icon(
                                    onPressed: _paying ? null : _pay,
                                    icon: _paying
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.lock_outline),
                                    label: Text(
                                      _paying
                                          ? 'Processing...'
                                          : 'Pay ${formatMoney(booking.totalMinor, booking.currency)}',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: _paying ? null : _cancel,
                                    icon: const Icon(Icons.close),
                                    label: const Text('Cancel this booking'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.booking, required this.remaining});

  final Booking booking;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = booking.isPending;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pending
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            pending ? Icons.timer_outlined : Icons.receipt_long_outlined,
            color: pending ? theme.colorScheme.onPrimaryContainer : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.statusLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  pending
                      ? 'Hold expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
                      : 'Booking ${booking.id.substring(0, 8).toUpperCase()}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSheet extends StatelessWidget {
  const _PaymentSheet({
    required this.payment,
    required this.phone,
    required this.network,
  });

  final Payment payment;
  final String phone;
  final String network;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.phone_android,
                size: 32,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Approve the mobile money prompt',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'A simulated $network prompt was sent to $phone for '
              '${formatMoney(payment.amountMinor, payment.currency)}.\n\n'
              'Reference: ${payment.providerReference.substring(0, 18)}...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('Approve in demo'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Leave it pending'),
            ),
          ],
        ),
      ),
    );
  }
}
