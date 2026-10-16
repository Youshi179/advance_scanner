import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'models.dart';
import 'status.dart';

class Cfg {
  static const takerFee = 0.001; // per leg
  static const crossMin = 0.02, crossMax = 0.20;
  static const triMin = 0.01, triMax = 0.20;
  static const fundMin = 0.02, fundMax = 0.40; // per 8h
  static const minLiq = 500.0; // USDT
}

const stables = {
  'USDT', 'USDC', 'DAI', 'BUSD', 'TUSD', 'FDUSD', 'USDP', 'USDD', 'USDE',
  'PYUSD', 'USD1', 'USDS', 'UST', 'USD',
};
bool isStable(String s) => stables.contains(s);

/// USDT value of 1 unit of each asset (median of mids across exchanges).
Map<String, double> buildFx(Map<String, Map<String, Quote>> spot) {
  final tmp = <String, List<double>>{};
  for (final m in spot.values) {
    m.forEach((k, q) {
      final p = k.split('/');
      if (p[1] != 'USDT') return;
      tmp.putIfAbsent(p[0], () => []).add((q.bid + q.ask) / 2);
    });
  }
  final fx = <String, double>{for (final s in stables) s: 1.0};
  tmp.forEach((a, l) {
    if (isStable(a)) return;
    l.sort();
    fx[a] = l[l.length ~/ 2];
  });
  return fx;
}

// ------------------------------------------------------------ cross-exchange
List<CrossOpp> scanCross(Map<String, Map<String, Quote>> spot,
    Map<String, double> fx, WalletService wallet) {
  final byPair = <String, List<MapEntry<String, Quote>>>{};
  spot.forEach((ex, m) =>
      m.forEach((pair, q) => byPair.putIfAbsent(pair, () => []).add(MapEntry(ex, q))));

  final out = <CrossOpp>[];
  byPair.forEach((pair, list) {
    if (list.length < 2) return;
    final p = pair.split('/');
    final base = p[0], quote = p[1];
    if (isStable(base) && isStable(quote)) return; // skip stable-stable
    final fq = fx[quote];
    if (fq == null) return;

    // best buy (lowest ask) / best sell (highest bid) on different exchanges
    MapEntry<String, Quote>? bb, bs;
    var bestGross = -1.0;
    for (final b in list) {
      for (final s in list) {
        if (b.key == s.key) continue;
        final g = (s.value.bid - b.value.ask) / b.value.ask;
        if (g > bestGross) {
          bestGross = g;
          bb = b;
          bs = s;
        }
      }
    }
    if (bb == null || bs == null) return;
    final net = bestGross - 2 * Cfg.takerFee;
    if (net < Cfg.crossMin || net > Cfg.crossMax) return;

    final buyLiq = bb.value.askQty * bb.value.ask * fq;
    final sellLiq = bs.value.bidQty * bs.value.bid * fq;
    final liq = buyLiq < sellLiq ? buyLiq : sellLiq;
    if (liq < Cfg.minLiq) return;

    out.add(CrossOpp(
      pair: pair,
      base: base,
      quote: quote,
      buyEx: bb.key,
      sellEx: bs.key,
      buyAsk: bb.value.ask,
      sellBid: bs.value.bid,
      gross: bestGross,
      net: net,
      liq: liq,
      est: bb.value.est || bs.value.est,
      ws: wallet.check(bb.key, bs.key, base),
    ));
  });
  out.sort((a, b) => b.net.compareTo(a.net));
  return out;
}

// ---------------------------------------------------------------- triangular
/// USDT -> X -> Y -> USDT where X/USDT, Y/USDT and Y/X exist on one exchange.
List<TriOpp> scanTri(Map<String, Map<String, Quote>> spot) {
  final out = <TriOpp>[];
  const f = 1 - Cfg.takerFee;
  const f3 = f * f * f;
  double min3(double a, double b, double c) =>
      a < b ? (a < c ? a : c) : (b < c ? b : c);

  spot.forEach((ex, m) {
    final usdt = <String, Quote>{};
    m.forEach((k, q) {
      final p = k.split('/');
      if (p[1] == 'USDT') usdt[p[0]] = q;
    });
    m.forEach((k, yx) {
      final p = k.split('/');
      final y = p[0], x = p[1];
      if (x == 'USDT' || isStable(x) || isStable(y)) return;
      final qx = usdt[x], yu = usdt[y];
      if (qx == null || yu == null) return;

      final fwd = yu.bid / (qx.ask * yx.ask);
      final rev = (qx.bid * yx.bid) / yu.ask;
      final forward = fwd >= rev;
      final net = (forward ? fwd : rev) * f3 - 1;
      if (net < Cfg.triMin || net > Cfg.triMax) return;

      final double l1, l2, l3;
      if (forward) {
        l1 = qx.askQty * qx.ask;
        l2 = yx.askQty * yx.ask * qx.bid;
        l3 = yu.bidQty * yu.bid;
      } else {
        l1 = yu.askQty * yu.ask;
        l2 = yx.bidQty * yx.bid * qx.bid;
        l3 = qx.bidQty * qx.bid;
      }
      final liq = min3(l1, l2, l3);
      if (liq < Cfg.minLiq) return;

      out.add(TriOpp(
        exchange: ex,
        x: x,
        y: y,
        forward: forward,
        path: forward ? 'USDT → $x → $y → USDT' : 'USDT → $y → $x → USDT',
        net: net,
        liq: liq,
        est: qx.est || yx.est || yu.est,
      ));
    });
  });
  out.sort((a, b) => b.net.compareTo(a.net));
  return out;
}

// ------------------------------------------------------------------- funding
List<FundOpp> scanFunding(Map<String, Map<String, FR>> fund) {
  final byCoin = <String, Map<String, double>>{};
  fund.forEach((ex, m) =>
      m.forEach((c, fr) => byCoin.putIfAbsent(c, () => {})[ex] = fr.per8));

  final out = <FundOpp>[];
  byCoin.forEach((coin, rates) {
    final e = rates.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final lo = e.first, hi = e.last;

    if (e.length >= 2) {
      final edge = (hi.value - lo.value).abs();
      if (edge >= Cfg.fundMin && edge <= Cfg.fundMax) {
        out.add(FundOpp(
            coin: coin, hiEx: hi.key, hiRate: hi.value, loEx: lo.key,
            loRate: lo.value, edge: edge, single: false));
        return;
      }
    }
    // single-exchange carry: largest |rate|
    final top = e.reduce((a, b) => a.value.abs() >= b.value.abs() ? a : b);
    final edge = top.value.abs();
    if (edge >= Cfg.fundMin && edge <= Cfg.fundMax) {
      out.add(FundOpp(
          coin: coin, hiEx: top.key, hiRate: top.value, loEx: top.key,
          loRate: top.value, edge: edge, single: true));
    }
  });
  out.sort((a, b) => b.edge.compareTo(a.edge));
  return out;
}

// ---------------------------------------------------------------- controller
enum WalletFilter { all, greenOnly, hideRed }

class ScannerController extends ChangeNotifier {
  final wallet = WalletService();
  Scan? scan;
  bool loading = false;
  String query = '';
  int tab = 0;
  WalletFilter filter = WalletFilter.all;
  final progress = ValueNotifier<double>(0);

  Timer? _scanTimer, _tick;
  DateTime _started = DateTime.now();
  bool _disposed = false;

  void start() {
    refresh();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final s = DateTime.now().difference(_started).inMilliseconds / 60000;
      progress.value = s.clamp(0.0, 1.0);
    });
  }

  void _arm() {
    _scanTimer?.cancel();
    _scanTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  void setQuery(String v) {
    query = v;
    notifyListeners();
  }

  void setTab(int v) {
    tab = v;
    notifyListeners();
  }

  void setFilter(WalletFilter v) {
    filter = v;
    notifyListeners();
  }

  bool passes(WS w) => switch (filter) {
        WalletFilter.all => true,
        WalletFilter.greenOnly => w.state == WsState.ok,
        WalletFilter.hideRed => w.state != WsState.blocked,
      };

  String _msg(Object e) {
    if (e is TimeoutException) return 'timeout';
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 70 ? '${s.substring(0, 70)}…' : s;
  }

  Future<void> refresh({bool forceWallet = false}) async {
    if (loading) return;
    loading = true;
    _started = DateTime.now();
    _arm();
    notifyListeners();

    final errors = <String>[];
    final spot = <String, Map<String, Quote>>{};
    final fund = <String, Map<String, FR>>{};

    Future<void> run<T>(String label, Future<T> Function() f, void Function(T) ok) async {
      try {
        ok(await f());
      } catch (e) {
        errors.add('$label: ${_msg(e)}');
      }
    }

    try {
      await Future.wait([
        for (final ex in exchanges)
          run('$ex spot', spotFetchers[ex]!, (m) => spot[ex] = m),
        for (final ex in exchanges)
          run('$ex funding', fundFetchers[ex]!, (m) => fund[ex] = m),
        wallet.refresh(errors, force: forceWallet),
      ]);

      final fx = buildFx(spot);
      scan = Scan(
        cross: scanCross(spot, fx, wallet),
        tri: scanTri(spot),
        fund: scanFunding(fund),
        spotOk: spot.length,
        fundOk: fund.length,
        total: exchanges.length,
        errors: errors,
        time: DateTime.now(),
      );
    } catch (e) {
      errors.add('scan: ${_msg(e)}');
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    _tick?.cancel();
    progress.dispose();
    super.dispose();
  }
}
