import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets.dart' show SkorxLogo;
import '../data/plans.dart';
import '../data/subscription.dart';
import '../subscription_controller.dart';

/// The player's SkorX Pro payments, newest first. Kept after Pro ends.
final billingHistoryProvider = FutureProvider<List<BillingRecord>>((ref) {
  // A new plan (a payment, a renewal) means a new row.
  ref.watch(subscriptionProvider.select((s) => s.value));
  return ref.watch(billingRepositoryProvider).history();
});

final invoiceProvider = FutureProvider.family<Invoice, String>((ref, orderId) => ref.watch(billingRepositoryProvider).invoice(orderId));

String _statusWord(BillingStatus s) => switch (s) {
      BillingStatus.paid => 'Paid',
      BillingStatus.pending => 'Pending',
      BillingStatus.failed => 'Failed',
      BillingStatus.cancelled => 'Cancelled',
      BillingStatus.refunded => 'Refunded',
    };

/// Billing history rows; [limit] shows the latest few with a link to all.
class BillingHistoryList extends ConsumerWidget {
  const BillingHistoryList({super.key, this.limit});

  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(billingHistoryProvider);
    final all = history.value ?? const <BillingRecord>[];
    final shown = limit == null ? all : all.take(limit!).toList();
    return Column(
      key: const Key('billingHistory'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SxSection(
          'Billing history',
          action: limit != null && all.length > limit! ? 'All' : null,
          onAction: () => context.push('/player/billing'),
        ),
        switch (history) {
          AsyncData() when all.isEmpty => const EmptyBlock(
              icon: Icons.receipt_long_outlined,
              title: 'No payments yet',
              message: 'Your SkorX Pro payments and invoices appear here.',
              compact: true,
            ),
          AsyncData() => SxRows(children: [for (final r in shown) _BillingRow(record: r)]),
          AsyncError() => ErrorBlock(message: 'Your payments did not load.', onRetry: () => ref.invalidate(billingHistoryProvider)),
          _ => const SkeletonList(rows: 2),
        },
      ],
    );
  }
}

class _BillingRow extends StatelessWidget {
  const _BillingRow({required this.record});

  final BillingRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final r = record;
    final color = switch (r.status) {
      BillingStatus.paid => c.volt,
      BillingStatus.pending => c.caution,
      _ => c.inkMuted,
    };
    return Semantics(
      button: r.hasInvoice,
      label: '${billingDate(r.date)}, SkorX Pro ${r.plan.label}, ${formatPaise(r.totalPaise)}, ${_statusWord(r.status)}',
      excludeSemantics: true,
      child: Tappable(
        key: Key('billing-${r.orderId}'),
        radius: 0,
        onTap: r.hasInvoice ? () => context.push('/player/billing/${Uri.encodeComponent(r.orderId)}') : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sx.s12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(billingDate(r.date), style: SxType.caption(c.inkMuted, size: 12.5)),
                    const SizedBox(height: 2),
                    Text('SkorX Pro ${r.plan.label}${r.renewal ? ' · renewal' : ''}', style: SxType.heading(c.ink, size: 15)),
                    Text(
                      '₹${r.plan.price} + GST${r.discountPaise > 0 ? ' · ${r.couponCode ?? 'coupon'} −${formatPaise(r.discountPaise)}' : ''}',
                      style: SxType.caption(c.inkMuted, size: 12.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatPaise(r.totalPaise), style: SxType.number(17, c.ink, weight: FontWeight.w800)),
                  Text(_statusWord(r.status).toUpperCase(), style: SxType.label(color, size: 11)),
                  if (r.hasInvoice)
                    Text('Invoice ›', style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 12).copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile › Billing & payments.
class BillingHistoryPage extends ConsumerWidget {
  const BillingHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/profile')),
              const SxTitleBar(title: 'Billing & payments'),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref.refresh(billingHistoryProvider.future),
                  color: c.onVolt,
                  backgroundColor: c.voltFill,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                    children: [
                      const BillingHistoryList(),
                      const SizedBox(height: Sx.s16),
                      Text('Amounts include GST. Tap a paid row for its invoice.', style: SxType.caption(c.inkMuted, size: 12.5)),
                    ],
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

/// One invoice, and a way to keep it: saved as an image through the
/// phone's share sheet (PDF once the server renders them: [Invoice.pdfUrl]).
class InvoicePage extends ConsumerStatefulWidget {
  const InvoicePage({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends ConsumerState<InvoicePage> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _download(Invoice inv) async {
    setState(() => _busy = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${inv.number}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        subject: 'SkorX invoice ${inv.number}',
        text: _invoiceText(inv),
      ));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _invoiceText(inv)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open sharing. Invoice details copied instead.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(invoiceProvider(widget.orderId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(
                title: 'Invoice',
                onBack: () => context.canPop() ? context.pop() : context.go('/player/billing'),
              ),
              Expanded(
                child: switch (inv) {
                  AsyncData(:final value) => ListView(
                      key: const Key('invoice'),
                      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s24),
                      children: [RepaintBoundary(key: _card, child: InvoiceSheet(invoice: value))],
                    ),
                  AsyncError(:final error) => EmptyBlock(
                      icon: Icons.receipt_long_outlined,
                      title: 'Invoice not available',
                      message: error is ApiException ? error.message : 'This invoice did not load.',
                      action: SxButton.secondary(
                        label: 'Try again',
                        expand: false,
                        onPressed: () => ref.invalidate(invoiceProvider(widget.orderId)),
                      ),
                    ),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: Skeleton(height: 520, radius: Sx.radiusLg)),
                },
              ),
              if (inv.value case final value?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                  child: SxButton(
                    key: const Key('downloadInvoice'),
                    label: 'Download invoice',
                    icon: Icons.download_rounded,
                    busy: _busy,
                    onPressed: () => _download(value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _invoiceText(Invoice i) => [
      '${i.sellerName} · Tax invoice ${i.number}',
      'Date: ${billingDate(i.date)}',
      'Billed to: ${i.customerName}${i.customerPhone == null ? '' : ' · ${i.customerPhone}'}',
      'SkorX Pro ${i.plan.label}${i.periodStart == null ? '' : ' · ${billingDate(i.periodStart!)} – ${billingDate(i.periodEnd!)}'}',
      'Plan ${formatPaise(i.basePaise)}',
      if (i.discountPaise > 0) 'Discount${i.couponCode == null ? '' : ' (${i.couponCode})'} ${formatPaise(-i.discountPaise)}',
      'GST ${(i.gstRate * 100).toStringAsFixed(0)}% ${formatPaise(i.gstPaise)}',
      'Total paid ${formatPaise(i.totalPaise)}',
      'Payment ${i.paymentId ?? '—'} · Order ${i.orderId}',
    ].join('\n');

/// The invoice itself: a light paper sheet in both themes, so it reads (and
/// saves) as a document.
class InvoiceSheet extends StatelessWidget {
  const InvoiceSheet({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    const ink = Color(0xFF0B1C33);
    const muted = Color(0xFF5B6778);
    const line = Color(0xFFDDE4EC);
    Widget row(String label, String value, {bool strong = false, Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: strong ? SxType.heading(ink, size: 16) : SxType.body(muted, size: 14))),
              const SizedBox(width: Sx.s12),
              Flexible(
                child: Text(
                  value,
                  key: key,
                  textAlign: TextAlign.end,
                  style: strong ? SxType.number(20, ink, weight: FontWeight.w800) : SxType.body(ink, size: 14),
                ),
              ),
            ],
          ),
        );
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: Sx.s20, bottom: Sx.s8),
          child: Text(t, style: SxType.label(muted, size: 11)),
        );
    return Container(
      padding: const EdgeInsets.all(Sx.s24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Sx.radius), border: Border.all(color: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SkorxLogo(height: 28),
              const SizedBox(width: Sx.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TAX INVOICE', style: SxType.label(muted, size: 11)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(i.number, key: const Key('invoiceNumber'), style: SxType.heading(ink, size: 15)),
                    ),
                    Text(billingDate(i.date), style: SxType.caption(muted, size: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          if (i.testMode) ...[
            const SizedBox(height: Sx.s12),
            Text('TEST MODE · NOT A REAL PAYMENT', style: SxType.label(const Color(0xFFB45309), size: 11)),
          ],
          heading('FROM'),
          Text(i.sellerName, style: SxType.body(ink, size: 14).copyWith(fontWeight: FontWeight.w700)),
          if (i.sellerAddress != null) Text(i.sellerAddress!, style: SxType.caption(muted)),
          if (i.sellerGstin != null) Text('GSTIN ${i.sellerGstin}', style: SxType.caption(muted)),
          heading('BILLED TO'),
          Text(i.customerName, style: SxType.body(ink, size: 14).copyWith(fontWeight: FontWeight.w700)),
          if (i.customerEmail != null) Text(i.customerEmail!, style: SxType.caption(muted)),
          if (i.customerPhone != null) Text(formatPhone(i.customerPhone!), style: SxType.caption(muted)),
          heading('PLAN'),
          row('SkorX Pro · ${i.plan.label}', i.plan.label == 'Annual' ? 'Billed yearly' : 'Billed monthly'),
          if (i.periodStart != null && i.periodEnd != null)
            row('Subscription', '${billingDate(i.periodStart!)} – ${billingDate(i.periodEnd!)}'),
          const Divider(height: Sx.s32, color: line),
          row('Base amount', formatPaise(i.basePaise)),
          if (i.discountPaise > 0) row('Discount${i.couponCode == null ? '' : ' (${i.couponCode})'}', formatPaise(-i.discountPaise)),
          row('GST ${(i.gstRate * 100).toStringAsFixed(i.gstRate * 100 % 1 == 0 ? 0 : 1)}%', formatPaise(i.gstPaise)),
          const Divider(height: Sx.s24, color: line),
          row('Total paid', formatPaise(i.totalPaise), strong: true, key: const Key('invoiceTotal')),
          heading('PAYMENT'),
          row('Status', 'Paid'),
          row('Payment ID', i.paymentId ?? '—'),
          row('Order ID', i.orderId),
          row('Razorpay order', i.razorpayOrderId),
        ],
      ),
    );
  }
}
