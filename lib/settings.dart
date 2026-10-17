import 'package:flutter/material.dart';
import 'data/status.dart';
import 'main.dart' show mint, card, amber;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ctl = {for (final e in keyedExchanges) e: List.generate(3, (_) => TextEditingController())};
  final saved = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final e in keyedExchanges) {
      final c = await KeyStore.load(e);
      if (c != null) {
        ctl[e]![0].text = c.key;
        ctl[e]![1].text = c.secret;
        ctl[e]![2].text = c.pass;
        saved[e] = true;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _save(String e) async {
    final c = ctl[e]!;
    if (c[0].text.trim().isEmpty || c[1].text.trim().isEmpty) return;
    await KeyStore.save(e, Creds(c[0].text, c[1].text, c[2].text));
    setState(() => saved[e] = true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e keys saved securely')));
  }

  Future<void> _remove(String e) async {
    await KeyStore.remove(e);
    for (final c in ctl[e]!) {
      c.clear();
    }
    setState(() => saved[e] = false);
  }

  Widget _field(TextEditingController c, String label, {bool secret = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: secret,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Settings'), backgroundColor: Colors.transparent),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: amber.withOpacity(.12), borderRadius: BorderRadius.circular(14)),
          child: const Text(
              '⚠ Use READ-ONLY keys with withdrawals disabled. Keys are stored with flutter_secure_storage and only used to read deposit/withdraw status.'),
        ),
        const SizedBox(height: 12),
        for (final e in keyedExchanges)
          Card(
            color: card,
            child: ExpansionTile(
              title: Text(e),
              subtitle: Text(saved[e] == true ? 'Key saved' : 'No key', style: TextStyle(color: saved[e] == true ? mint : Colors.white54)),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                _field(ctl[e]![0], 'API Key'),
                _field(ctl[e]![1], 'API Secret', secret: true),
                if (e == 'OKX') _field(ctl[e]![2], 'Passphrase', secret: true),
                Row(children: [
                  Expanded(child: FilledButton(onPressed: () => _save(e), child: const Text('Save'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton(onPressed: () => _remove(e), child: const Text('Remove'))),
                ]),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Card(
          color: card,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Public (no key needed): KuCoin, Gate.io, Bitget — wallet status works without keys.\n'
                'Prices and funding for all 8 exchanges are public.\nOKX requests go to www.okx.cab.'),
          ),
        ),
      ]),
    );
  }
}