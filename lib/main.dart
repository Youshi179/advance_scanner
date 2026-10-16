import 'dart:math';
import 'package:flutter/material.dart';
import 'data/models.dart';
import 'data/scanner.dart';
import 'settings.dart';

const mint = Color(0xFF2EF2B4);
const cyan = Color(0xFF35C8FF);
const violet = Color(0xFF8B5CF6);
const pink = Color(0xFFFF5C8A);
const amber = Color(0xFFFFB84D);
const kBg = Color(0xFF0A0D16);
const kCard = Color(0xFF131829);

void main() => runApp(const AdvanceApp());

class AdvanceApp extends StatelessWidget {
  const AdvanceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Advance Scanner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(
              primary: mint, secondary: cyan, surface: kCard),
        ),
        home: const HomePage(),
      );
}

// ---------------------------------------------------------------- formatters
String fmtPrice(double p) {
  if (p >= 1000) return p.toStringAsFixed(2);
  if (p >= 1) return p.toStringAsFixed(4);
  if (p >= 0.01) return p.toStringAsFixed(6);
  var s = p.toStringAsFixed(10);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s;
}

String fmtUsd(double v) {
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1e3) return '\$${(v / 1e3).toStringAsFixed(1)}K';
  return '\$${v.toStringAsFixed(0)}';
}

String pct(double v, [int d = 2]) => '${(v * 100).toStringAsFixed(d)}%';
String two(int n) => n.toString().padLeft(2, '0');
String clock(DateTime t) => '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

LinearGradient grad(List<Color> c) => LinearGradient(
    colors: c, begin: Alignment.topLeft, end: Alignment.bottomRight);

// ---------------------------------------------------------------------- home
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final c = ScannerController();
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    c.dispose();
    search.dispose();
    super.dispose();
  }

  void _showErrors(Scan? s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Scan errors'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in s?.errors ?? <String>[])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• $e', style: const TextStyle(fontSize: 12.5)),
                )
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Close'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0D16), Color(0xFF111033), Color(0xFF0A0D16)],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(listenable: c, builder: (_, __) => _content()),
        ),
      ),
    );
  }

  Widget _content() {
    final s = c.scan;
    final q = c.query.trim().toLowerCase();
    bool m(String t) => q.isEmpty || t.toLowerCase().contains(q);

    final cross = [
      for (final o in s?.cross ?? <CrossOpp>[])
        if (m('${o.pair} ${o.buyEx} ${o.sellEx}') && c.passes(o.ws)) o
    ];
    final tri = [
      for (final o in s?.tri ?? <TriOpp>[])
        if (m('${o.x} ${o.y} ${o.exchange}')) o
    ];
    final fund = [
      for (final o in s?.fund ?? <FundOpp>[])
        if (m('${o.coin} ${o.hiEx} ${o.loEx}')) o
    ];

    final count = [cross.length, tri.length, fund.length][c.tab];
    final itemBuilder = switch (c.tab) {
      0 => (BuildContext ctx, int i) {
          final o = cross[i];
          return FadeSlide(
              key: ValueKey('c${o.pair}${o.buyEx}${o.sellEx}'),
              index: i,
              child: CrossCard(o));
        },
      1 => (BuildContext ctx, int i) {
          final o = tri[i];
          return FadeSlide(
              key: ValueKey('t${o.exchange}${o.x}${o.y}${o.forward}'),
              index: i,
              child: TriCard(o));
        },
      _ => (BuildContext ctx, int i) {
          final o = fund[i];
          return FadeSlide(
              key: ValueKey('f${o.coin}${o.hiEx}${o.loEx}'),
              index: i,
              child: FundCard(o, onTap: () => showCalc(ctx, o)));
        },
    };

    final errCount = s?.errors.length ?? 0;
    final status = s == null
        ? 'Scanning…'
        : '${s.spotOk}/${s.total} spot • ${s.fundOk}/${s.total} funding • ${clock(s.time)}';

    return Column(
      children: [
        // header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (r) =>
                      const LinearGradient(colors: [mint, cyan, violet]).createShader(r),
                  child: const Text('Advance Scanner',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: .3)),
                ),
              ),
              PopupMenuButton<WalletFilter>(
                tooltip: 'Wallet filter',
                icon: Icon(Icons.account_balance_wallet_outlined,
                    color: c.filter == WalletFilter.all ? Colors.white70 : mint),
                color: kCard,
                onSelected: c.setFilter,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: WalletFilter.all, child: Text('Show all')),
                  PopupMenuItem(
                      value: WalletFilter.greenOnly,
                      child: Text('🟢 Only deposit/withdraw OK')),
                  PopupMenuItem(
                      value: WalletFilter.hideRed, child: Text('Hide 🔴 blocked')),
                ],
              ),
              IconButton(
                tooltip: 'API settings',
                icon: const Icon(Icons.vpn_key_outlined, color: Colors.white70),
                onPressed: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SettingsPage(c: c)));
                },
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: c.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: mint))
                    : const Icon(Icons.refresh_rounded, color: Colors.white70),
                onPressed: c.loading ? null : () => c.refresh(forceWallet: true),
              ),
            ],
          ),
        ),
        // search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: search,
            onChanged: c.setQuery,
            decoration: InputDecoration(
              hintText: 'Search coin or pair (BTC, ETH/EUR…)',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: c.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        search.clear();
                        c.setQuery('');
                      }),
              filled: true,
              fillColor: kCard,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        // tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _TabPill('Cross', cross.length, c.tab == 0, mint, () => c.setTab(0)),
              const SizedBox(width: 8),
              _TabPill('Tri', tri.length, c.tab == 1, cyan, () => c.setTab(1)),
              const SizedBox(width: 8),
              _TabPill('Funding', fund.length, c.tab == 2, violet, () => c.setTab(2)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // progress
        ValueListenableBuilder<double>(
          valueListenable: c.progress,
          builder: (_, v, __) => LinearProgressIndicator(
            value: v,
            minHeight: 2,
            backgroundColor: Colors.white10,
            color: cyan,
          ),
        ),
        // status bar
        InkWell(
          onTap: errCount > 0 ? () => _showErrors(s) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                    child: Text(status,
                        style: const TextStyle(fontSize: 11.5, color: Colors.white54))),
                if (errCount > 0)
                  Text('⚠ $errCount errors',
                      style: const TextStyle(fontSize: 11.5, color: amber)),
              ],
            ),
          ),
        ),
        // list
        Expanded(
          child: RefreshIndicator(
            color: mint,
            backgroundColor: kCard,
            onRefresh: () => c.refresh(forceWallet: true),
            child: s == null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: CircularProgressIndicator(color: mint)),
                      SizedBox(height: 16),
                      Center(
                          child: Text('Scanning 8 exchanges…',
                              style: TextStyle(color: Colors.white54))),
                    ],
                  )
                : count == 0
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                              child: Text('No opportunities match right now',
                                  style: TextStyle(color: Colors.white54))),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: min(count, 300),
                        itemBuilder: itemBuilder,
                      ),
          ),
        ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final int n;
  final bool sel;
  final Color color;
  final VoidCallback onTap;
  const _TabPill(this.label, this.n, this.sel, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: sel ? grad([color.withValues(alpha: .35), color.withValues(alpha: .12)]) : null,
              color: sel ? null : kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? color : Colors.white10),
            ),
            child: Center(
              child: Text('$label · $n',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: sel ? color : Colors.white60)),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- animation
class FadeSlide extends StatelessWidget {
  final int index;
  final Widget child;
  const FadeSlide({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 350 + min(index, 8) * 50),
        curve: Curves.easeOutCubic,
        builder: (_, v, ch) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: ch),
        ),
        child: child,
      );
}

// --------------------------------------------------------------------- cards
class _Shell extends StatelessWidget {
  final Color accent;
  final Widget child;
  final VoidCallback? onTap;
  const _Shell({required this.accent, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: grad([kCard, accent.withValues(alpha: .08)]),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: .28)),
              ),
              child: child,
            ),
          ),
        ),
      );
}

class _ProfitBadge extends StatelessWidget {
  final String text;
  final List<Color> colors;
  const _ProfitBadge(this.text, this.colors);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            gradient: grad(colors), borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF06241B), fontWeight: FontWeight.w800, fontSize: 14)),
      );
}

class _Leg extends StatelessWidget {
  final String tag, ex, price;
  final Color color;
  const _Leg(this.tag, this.ex, this.price, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(5)),
                child: Text(tag,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0A0D16))),
              ),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(ex,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 6),
            Text(price,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

Color wsColor(WsState s) => switch (s) {
      WsState.ok => mint,
      WsState.blocked => pink,
      WsState.unknown => amber,
    };

class CrossCard extends StatelessWidget {
  final CrossOpp o;
  const CrossCard(this.o, {super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        accent: mint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(o.pair,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              _ProfitBadge('+${pct(o.net)}', const [mint, cyan]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Leg('BUY', o.buyEx, fmtPrice(o.buyAsk), mint)),
              const SizedBox(width: 8),
              Expanded(child: _Leg('SELL', o.sellEx, fmtPrice(o.sellBid), pink)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.water_drop_outlined, size: 14, color: cyan),
              const SizedBox(width: 4),
              Text('Liq ${o.est ? '~' : ''}${fmtUsd(o.liq)}',
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
              const Spacer(),
              Text('gross ${pct(o.gross)} • fees −0.20%',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text(o.ws.icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(o.ws.msg,
                      style: TextStyle(fontSize: 12, color: wsColor(o.ws.state)))),
            ]),
          ],
        ),
      );
}

class TriCard extends StatelessWidget {
  final TriOpp o;
  const TriCard(this.o, {super.key});
  @override
  Widget build(BuildContext context) => _Shell(
        accent: cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text('${o.y}/${o.x}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              _ProfitBadge('+${pct(o.net)}', const [cyan, violet]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: cyan.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cyan.withValues(alpha: .4))),
                child: Text(o.exchange,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(o.path,
                      style: const TextStyle(fontSize: 13, color: Colors.white70))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.water_drop_outlined, size: 14, color: cyan),
              const SizedBox(width: 4),
              Text('Liq ${o.est ? '~' : ''}${fmtUsd(o.liq)}',
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
              const Spacer(),
              Text(o.forward ? 'forward' : 'reverse',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
            ]),
          ],
        ),
      );
}

class FundCard extends StatelessWidget {
  final FundOpp o;
  final VoidCallback onTap;
  const FundCard(this.o, {super.key, required this.onTap});

  Widget _rate(String label, String ex, double r, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: .35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label • $ex',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
            const SizedBox(height: 4),
            Text('${r >= 0 ? '+' : ''}${pct(r, 3)} /8h',
                style: TextStyle(fontWeight: FontWeight.w800, color: c)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => _Shell(
        accent: violet,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text('${o.coin}  perp',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              _ProfitBadge('${pct(o.edge)} /8h', const [violet, pink]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _rate('HIGH', o.hiEx, o.hiRate, pink),
              if (!o.single) ...[
                const SizedBox(width: 8),
                _rate('LOW', o.loEx, o.loRate, mint),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.swap_vert_rounded, size: 16, color: amber),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(o.strategy,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: amber))),
              const Icon(Icons.calculate_outlined, size: 16, color: Colors.white38),
            ]),
          ],
        ),
      );
}

// --------------------------------------------------------- profit calculator
void showCalc(BuildContext context, FundOpp o) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _CalcSheet(o),
    ),
  );
}

class _CalcSheet extends StatefulWidget {
  final FundOpp o;
  const _CalcSheet(this.o);
  @override
  State<_CalcSheet> createState() => _CalcSheetState();
}

class _CalcSheetState extends State<_CalcSheet> {
  final ctl = TextEditingController(text: '1000');
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Widget _row(String l, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(l, style: const TextStyle(color: Colors.white60)),
          const Spacer(),
          Text('\$${v.toStringAsFixed(2)}',
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: bold ? mint : Colors.white,
                  fontSize: bold ? 17 : 15)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    final cap = double.tryParse(ctl.text.replaceAll(',', '.')) ?? 0;
    final p8 = cap * o.edge;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${o.coin} funding calculator',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(o.strategy, style: const TextStyle(color: amber, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Capital per leg (USDT)',
                prefixText: '\$ ',
                filled: true,
                fillColor: kBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            _row('Per 8h  (${pct(o.edge, 3)})', p8, bold: true),
            _row('Daily (×3)', p8 * 3),
            _row('Weekly', p8 * 21),
            _row('Monthly (30d)', p8 * 90),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Text('APR (simple)', style: TextStyle(color: Colors.white60)),
                const Spacer(),
                Text('${(o.edge * 3 * 365 * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: cyan)),
              ]),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gross of trading fees, spread, borrow costs and rate changes. '
              'Funding rates move every interval — not guaranteed.',
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
