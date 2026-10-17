import 'dart:async';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'data/api.dart';
import 'data/models.dart';
import 'data/scanner.dart';
import 'data/status.dart';
import 'settings.dart';

const mint = Color(0xFF2EF2B4), cyan = Color(0xFF35C8FF), violet = Color(0xFF8B5CF6);
const pink = Color(0xFFFF5C8A), amber = Color(0xFFFFB84D);
const bg = Color(0xFF0B0F1A), card = Color(0xFF131A2B);

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Advance Scanner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: mint, secondary: cyan, surface: card),
        ),
        home: const Home(),
      );
}

// ───────────── Controller ─────────────
class _Job {
  final Map<String, Map<String, Quote>> spot;
  final Map<String, Map<String, double>> fund;
  final Map<String, Map<String, WS>> wal;
  const _Job(this.spot, this.fund, this.wal);
}

// Runs in a background isolate (inline on web).
(List<CrossOpp>, List<TriOpp>, List<FundOpp>) _scanJob(_Job j) =>
    (scanCross(j.spot, j.wal), scanTri(j.spot), scanFunding(j.fund));

class ScannerController extends ChangeNotifier {
  Scan? scan;
  bool loading = false;
  String query = '';
  int tab = 0, wf = 0; // wf: 0 all, 1 green only, 2 hide red
  final progress = ValueNotifier<double>(0); // separate: ticking must not rebuild the list
  int _sec = 0;
  Timer? _refresh, _tick;

  final _spot = <String, Map<String, Quote>>{};
  final _fund = <String, Map<String, double>>{};
  final _wal = <String, Map<String, WS>>{};
  final _walAt = <String, DateTime>{};
  final _errors = <String, String>{};
  bool _scanning = false, _dirty = false, _disposed = false;

  void start() {
    refresh();
    _refresh = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _sec = (_sec + 1) % 60;
      progress.value = _sec / 60;
    });
  }

  void set({String? q, int? t, int? w}) {
    query = q ?? query;
    tab = t ?? tab;
    wf = w ?? wf;
    notifyListeners();
  }

  Future<void> _run<T>(String label, Future<T> Function() f, void Function(T) ok, void Function() fail) async {
    try {
      ok(await f());
      _errors.remove(label);
    } catch (e) {
      fail();
      _errors[label] = '$label: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    unawaited(_rescan()); // progressive: show results as each exchange arrives
  }

  Future<void> refresh({bool forceWallet = false}) async {
    if (loading) return;
    loading = true;
    _sec = 0;
    progress.value = 0;
    notifyListeners();
    final now = DateTime.now();
    await Future.wait([
      for (final e in exchanges) _run('$e spot', spotFetchers[e]!, (m) => _spot[e] = m, () => _spot.remove(e)),
      for (final e in exchanges) _run('$e funding', fundFetchers[e]!, (m) => _fund[e] = m, () => _fund.remove(e)),
      // wallet status changes rarely: refetch only every 10 min (or after keys change)
      for (final e in exchanges)
        if (forceWallet || _walAt[e] == null || now.difference(_walAt[e]!).inMinutes >= 10)
          _run('$e wallet', () => fetchWallet(e), (m) {
            if (m != null) {
              _wal[e] = m;
              _walAt[e] = DateTime.now();
            } else {
              _wal.remove(e);
            }
          }, () {}),
    ]);
    loading = false;
    await _rescan();
    if (!_disposed) notifyListeners();
  }

  Future<void> _rescan() async {
    if (_scanning) {
      _dirty = true;
      return;
    }
    _scanning = true;
    try {
      do {
        _dirty = false;
        if (_spot.isEmpty && _fund.isEmpty) break;
        final r = await compute(_scanJob, _Job(Map.of(_spot), Map.of(_fund), Map.of(_wal)));
        if (_disposed) return;
        scan = Scan(r.$1, r.$2, r.$3, _spot.length, _fund.length, _errors.values.toList(), DateTime.now());
        notifyListeners();
      } while (_dirty);
    } catch (e) {
      _errors['scan'] = 'scan: $e';
    } finally {
      _scanning = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refresh?.cancel();
    _tick?.cancel();
    progress.dispose();
    super.dispose();
  }
}

// ───────────── helpers ─────────────
String pct(double v) => (v * 100).toStringAsFixed(2);
String fp(double v) => v >= 100 ? v.toStringAsFixed(2) : v >= 1 ? v.toStringAsFixed(4) : v >= 0.01 ? v.toStringAsFixed(6) : v.toStringAsFixed(10);
String fl(double v) => v >= 1e6 ? '\$${(v / 1e6).toStringAsFixed(2)}M' : v >= 1e3 ? '\$${(v / 1e3).toStringAsFixed(1)}K' : '\$${v.toStringAsFixed(0)}';
String two(int n) => n.toString().padLeft(2, '0');

class Entrance extends StatelessWidget {
  final int i;
  final Widget child;
  const Entrance(this.i, this.child, {super.key});
  @override
  Widget build(BuildContext context) => i >= 8
      ? child // no extra opacity/transform layers for the rest of the list
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + i * 40),
          curve: Curves.easeOutCubic,
          builder: (_, v, ch) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: ch)),
          child: child,
        );
}

Widget badge(String t, Color c, {bool filled = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: filled ? c : c.withOpacity(.16), borderRadius: BorderRadius.circular(8)),
      child: Text(t, style: TextStyle(color: filled ? Colors.black : c, fontWeight: FontWeight.w800, fontSize: 11)),
    );

Widget profitBadge(double v, {List<Color> g = const [mint, cyan]}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(gradient: LinearGradient(colors: g), borderRadius: BorderRadius.circular(20)),
      child: Text('+${pct(v)}%', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
    );

Widget cardBox(Widget child, {VoidCallback? onTap}) => Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: child)),
      ),
    );

// ───────────── Home ─────────────
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final c = ScannerController();
  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Widget leg(String label, String ex, double p, Color col) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: col.withOpacity(.08), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [badge(label, col, filled: true), const SizedBox(width: 6), Flexible(child: Text(ex, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)))]),
          const SizedBox(height: 6),
          Text(fp(p), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget crossCard(CrossOpp o) {
    final col = {WStatus.ok: mint, WStatus.blocked: pink, WStatus.unknown: amber}[o.ws]!;
    final dot = {WStatus.ok: '🟢', WStatus.blocked: '🔴', WStatus.unknown: '🟡'}[o.ws]!;
    return cardBox(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(o.pair, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))), profitBadge(o.net)]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: leg('BUY', o.buyEx, o.buy, mint)), const SizedBox(width: 8), Expanded(child: leg('SELL', o.sellEx, o.sell, pink))]),
      const SizedBox(height: 10),
      Text('Liquidity ${fl(o.liq)}${o.est ? ' (est.)' : ''}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 6),
      Text('$dot ${o.wsMsg}', style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600)),
    ]));
  }

  Widget triCard(TriOpp o) => cardBox(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [badge(o.ex, cyan), const SizedBox(width: 8), badge(o.dir, violet), const Spacer(), profitBadge(o.net, g: const [violet, cyan])]),
        const SizedBox(height: 10),
        Text(o.path, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Min leg liquidity ${fl(o.liq)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]));

  Widget fundCard(FundOpp o) => cardBox(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(o.coin, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))), profitBadge(o.edge, g: const [amber, pink])]),
          const SizedBox(height: 10),
          if (!o.single)
            Row(children: [
              Expanded(child: _rate('HIGH', o.hiEx, o.hi, pink)),
              const SizedBox(width: 8),
              Expanded(child: _rate('LOW', o.loEx, o.lo, mint)),
            ])
          else
            _rate('RATE', o.hiEx, o.hi, amber),
          const SizedBox(height: 10),
          Text(o.strategy, style: const TextStyle(color: cyan, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          const Text('per 8h • tap for profit calculator', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: card, builder: (_) => CalcSheet(o)),
      );

  Widget _rate(String l, String ex, double r, Color col) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: col.withOpacity(.08), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [badge(l, col, filled: true), const SizedBox(width: 6), Flexible(child: Text(ex, overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 6),
          Text('${r >= 0 ? '+' : ''}${(r * 100).toStringAsFixed(3)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  void _errors(Scan s) => showDialog(
      context: context,
      builder: (_) => AlertDialog(
            title: const Text('Errors'),
            content: SingleChildScrollView(child: Text(s.errors.join('\n'))),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (ctx, _) {
            final s = c.scan;
            final q = c.query.toLowerCase();
            final cross = (s?.cross ?? []).where((o) => o.pair.toLowerCase().contains(q) && (c.wf == 0 || (c.wf == 1 ? o.ws == WStatus.ok : o.ws != WStatus.blocked))).toList();
            final tri = (s?.tri ?? []).where((o) => o.path.toLowerCase().contains(q) || o.ex.toLowerCase().contains(q)).toList();
            final fund = (s?.fund ?? []).where((o) => o.coin.toLowerCase().contains(q)).toList();
            final counts = [cross.length, tri.length, fund.length];
            final n = c.tab == 0 ? cross.length : c.tab == 1 ? tri.length : fund.length;
            Widget item(int i) => c.tab == 0 ? crossCard(cross[i]) : c.tab == 1 ? triCard(tri[i]) : fundCard(fund[i]);
            final wfCol = [Colors.white54, mint, amber][c.wf];
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
                child: Row(children: [
                  Expanded(
                    child: ShaderMask(
                      shaderCallback: (r) => const LinearGradient(colors: [mint, cyan, violet]).createShader(r),
                      child: const Text('Advance Scanner', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Wallet filter',
                    icon: Icon(Icons.account_balance_wallet_outlined, color: wfCol),
                    onPressed: () {
                      c.set(w: (c.wf + 1) % 3);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 1), content: Text(['Wallet filter: show all', 'Wallet filter: 🟢 only', 'Wallet filter: hide 🔴'][c.wf])));
                    },
                  ),
                  IconButton(icon: const Icon(Icons.vpn_key_outlined), onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
                    c.refresh(forceWallet: true);
                  }),
                  c.loading
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.refresh), onPressed: c.refresh),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: TextField(
                  onChanged: (v) => c.set(q: v),
                  decoration: InputDecoration(
                    hintText: 'Search coin or pair…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: card,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => c.set(t: i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: c.tab == i ? const LinearGradient(colors: [mint, cyan]) : null,
                            color: c.tab == i ? null : card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(child: Text('${['Cross', 'Tri', 'Funding'][i]} ${counts[i]}', style: TextStyle(fontWeight: FontWeight.w800, color: c.tab == i ? Colors.black : Colors.white70))),
                        ),
                      ),
                    ),
                ]),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 0), child: ClipRRect(borderRadius: BorderRadius.circular(4), child: ValueListenableBuilder<double>(valueListenable: c.progress, builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 3, color: violet, backgroundColor: Colors.white10)))),
              GestureDetector(
                onTap: s != null && s.errors.isNotEmpty ? () => _errors(s) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    s == null ? 'Scanning…' : '${s.spotOk}/8 spot • ${s.fundOk}/8 funding • ${two(s.time.hour)}:${two(s.time.minute)}:${two(s.time.second)}${s.errors.isEmpty ? '' : ' • ⚠ ${s.errors.length} errors'}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
              ),
              Expanded(
                child: s == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: c.refresh,
                        child: n == 0
                            ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No opportunities match', style: TextStyle(color: Colors.white38)))])
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: n,
                                itemBuilder: (_, i) => Entrance(i, item(i)),
                              ),
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ───────────── Profit calculator ─────────────
class CalcSheet extends StatefulWidget {
  final FundOpp o;
  const CalcSheet(this.o, {super.key});
  @override
  State<CalcSheet> createState() => _CalcSheetState();
}

class _CalcSheetState extends State<CalcSheet> {
  final t = TextEditingController(text: '1000');
  @override
  Widget build(BuildContext context) {
    final cap = double.tryParse(t.text) ?? 0, e = widget.o.edge;
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Text(l, style: const TextStyle(color: Colors.white60)), const Spacer(), Text(v, style: const TextStyle(fontWeight: FontWeight.w800, color: mint))]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${widget.o.coin} funding calculator', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(widget.o.strategy, style: const TextStyle(color: cyan, fontSize: 12)),
        const SizedBox(height: 14),
        TextField(
          controller: t,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Capital per leg (USDT)', border: OutlineInputBorder(), prefixText: '\$ '),
        ),
        const SizedBox(height: 10),
        row('Per 8h', '\$${(cap * e).toStringAsFixed(2)}'),
        row('Daily', '\$${(cap * e * 3).toStringAsFixed(2)}'),
        row('Weekly', '\$${(cap * e * 21).toStringAsFixed(2)}'),
        row('Monthly (30d)', '\$${(cap * e * 90).toStringAsFixed(2)}'),
        row('APR', '${(e * 3 * 365 * 100).toStringAsFixed(0)}%'),
        const SizedBox(height: 6),
        const Text('Gross of trading fees, slippage and funding-rate changes.', style: TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }
}