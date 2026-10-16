import 'package:flutter/material.dart';
import 'data/api.dart';
import 'data/scanner.dart';
import 'data/status.dart';
import 'main.dart' show mint, pink, amber, kBg, kCard;

class SettingsPage extends StatelessWidget {
  final ScannerController c;
  const SettingsPage({super.key, required this.c});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: kBg,
          title: const Text('API settings'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: amber.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: amber.withValues(alpha: .3)),
              ),
              child: const Text(
                'Use READ-ONLY keys only (no trading, no withdraw permission). '
                'Keys are stored encrypted on-device and are only used to read '
                'deposit/withdraw status.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 14),
            for (final ex in WalletService.needKey)
              _KeyTile(ex: ex, c: c, needPass: WalletService.needPass.contains(ex)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: kCard, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Public (no key needed)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Prices & funding: ${exchanges.join(', ')}\n'
                    'Wallet status: ${WalletService.publicEx.join(', ')}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _KeyTile extends StatefulWidget {
  final String ex;
  final ScannerController c;
  final bool needPass;
  const _KeyTile({required this.ex, required this.c, required this.needPass});
  @override
  State<_KeyTile> createState() => _KeyTileState();
}

class _KeyTileState extends State<_KeyTile> {
  final key = TextEditingController();
  final secret = TextEditingController();
  final pass = TextEditingController();
  bool saved = false, busy = false, hide = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    key.dispose();
    secret.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cr = await widget.c.wallet.keys.load(widget.ex);
    if (!mounted) return;
    setState(() {
      saved = cr != null;
      if (cr != null) {
        key.text = cr.key;
        secret.text = cr.secret;
        pass.text = cr.pass;
      }
    });
  }

  Future<void> _save() async {
    if (key.text.trim().isEmpty || secret.text.trim().isEmpty) return;
    if (widget.needPass && pass.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('OKX needs a passphrase')));
      return;
    }
    setState(() => busy = true);
    await widget.c.wallet.keys
        .save(widget.ex, Cred(key.text, secret.text, pass.text));
    await widget.c.refresh(forceWallet: true);
    if (!mounted) return;
    setState(() {
      busy = false;
      saved = true;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${widget.ex} key saved')));
  }

  Future<void> _remove() async {
    await widget.c.wallet.keys.remove(widget.ex);
    key.clear();
    secret.clear();
    pass.clear();
    widget.c.wallet.data.remove(widget.ex);
    await widget.c.refresh(forceWallet: true);
    if (!mounted) return;
    setState(() => saved = false);
  }

  InputDecoration _dec(String l) => InputDecoration(
        labelText: l,
        filled: true,
        fillColor: kBg,
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: kCard, borderRadius: BorderRadius.circular(14)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(widget.ex, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(saved ? 'Key saved' : 'No key',
                style: TextStyle(fontSize: 12, color: saved ? mint : Colors.white38)),
            leading: Icon(saved ? Icons.lock : Icons.lock_open,
                color: saved ? mint : Colors.white38),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              TextField(controller: key, decoration: _dec('API key')),
              const SizedBox(height: 8),
              TextField(
                controller: secret,
                obscureText: hide,
                decoration: _dec('API secret').copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(hide ? Icons.visibility : Icons.visibility_off, size: 18),
                    onPressed: () => setState(() => hide = !hide),
                  ),
                ),
              ),
              if (widget.needPass) ...[
                const SizedBox(height: 8),
                TextField(
                    controller: pass, obscureText: true, decoration: _dec('Passphrase')),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: mint, foregroundColor: kBg),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: saved ? _remove : null,
                  style: OutlinedButton.styleFrom(foregroundColor: pink),
                  child: const Text('Remove'),
                ),
              ]),
            ],
          ),
        ),
      );
}
