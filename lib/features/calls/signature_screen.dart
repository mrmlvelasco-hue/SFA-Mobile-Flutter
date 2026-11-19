import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import 'call_navigation.dart';
import 'call_state.dart';
import 'order_draft.dart';
import 'signature_pad.dart';

/// Digital Signature -- the customer signs, remarks are added, and the order is sent
/// (order/submit; queued when offline). The RN app's DigitalSignatureScreen.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key, required this.ctx, required this.draft});
  final CallContext ctx;
  final OrderDraft draft;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _signature = SignatureController();
  final _remarks = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _signature.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final image = await _signature.toDataUrl();
    if (!mounted) return;
    if (image == null) {
      await messageDialog(context, 'Signature', 'Please have the customer sign first.');
      return;
    }
    setState(() => _sending = true);
    final calls = context.read<CallState>();
    final result = await calls.submitOrder(
      routeCall: widget.ctx.raw,
      creditTerm: widget.ctx.text('credit_term'),
      signature: image,
      remarks: _remarks.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    final record = calls.record(widget.ctx.customerNumber);
    if (result.queued || result.envelope.isSuccess) {
      await messageDialog(context, result.queued ? 'Order Saved' : 'Order Submitted', record?.orderMessage ?? '');
      if (mounted) Navigator.of(context).popUntil((r) => r.settings.name == customerRouteName || r.isFirst);
    } else {
      await messageDialog(context, 'Order Not Accepted', result.envelope.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Digital Signature')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(widget.ctx.text('outlet_name'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('Total Estimated Amount: PHP ${numberWithDecimals(widget.draft.totalEstimated)}'),
          const SizedBox(height: 12),
          const Text('Customer Signature'),
          const SizedBox(height: 6),
          SignaturePad(key: const Key('signaturePad'), controller: _signature),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: _signature.clear, icon: const Icon(Icons.clear), label: const Text('Clear')),
          ),
          TextField(
            key: const Key('remarks'),
            controller: _remarks,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Remarks', border: OutlineInputBorder()),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            key: const Key('submitOrder'),
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? 'Sending...' : 'Submit Order'),
          ),
        ),
      ),
    );
  }
}
