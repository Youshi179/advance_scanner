import 'dart:math';
import 'api.dart';
import 'models.dart';

const fee = 0.0; // fees removed (was 0.001 per leg)
const minCross = 0.02, maxCross = 0.20;
const minTri = 0.01, maxTri = 0.20;
const minFund = 0.02, maxFund = 0.40; // per 8h
const minLiq = 500.0; // USDT

typedef Spot = Map<String, Map<String, Quote>>;

class _Px {
  final Spot s;
  final memo = <String, double>{};
  _Px(this.s);

  /// USDT value of 1 unit of [q] (handles fiat via Q/USDT or USDT/Q).
  double q2u(String ex, String q) {
    if (stables.contains(q)) return 1;
    return memo.putIfAbsent('$ex|$q', () {
      for (final e in [ex, ...s.keys]) {
        final m = s[e];
        if (m == null) continue;
        final a = m['$q/USDT'];
        if (a != null) return a.mid;
        final b = m['USDT/$q'];
        if (b != null) return 1 / b.mid;
      }
      return 0.0;
    });
  }
}

(WStatus, String) _wallet(Map<String, Map<String, WS>> wal, String base, String bx, String sx) {
  final wd = wal[bx]?[base]?.wd, dep = wal[sx]?[base]?.dep;
  if (wd == false || dep == false) {
    final msgs = [if (wd == false) '$bx withdraw closed', if (dep == false) '$sx deposit closed'];
    return (WStatus.blocked, msgs.join(' • '));
  }
  if (wd == true && dep == true) return (WStatus.ok, 'Withdraw ✓ $bx • Deposit ✓ $sx');
  return (WStatus.unknown, 'Wallet status unknown (add API keys / coin not listed)');
}

List<CrossOpp> scanCross(Spot spot, Map<String, Map<String, WS>> wal) {
  final px = _Px(spot);
  final by = <String, Map<String, Quote>>{};
  spot.forEach((ex, m) => m.forEach((p, q) => (by[p] ??= <String, Quote>{})[ex] = q));
  final out = <CrossOpp>[];
  by.forEach((pair, qs) {
    if (qs.length < 2) return;
    final pr = pair.split('/');
    final base = pr[0], quote = pr[1];
    if (stables.contains(base) && stables.contains(quote)) return;
    String? bx, sx;
    var best = -1.0;
    for (final b in qs.entries) {
      for (final s in qs.entries) {
        if (b.key == s.key) continue;
        final net = (s.value.bid - b.value.ask) / b.value.ask - 2 * fee;
        if (net > best) {
          best = net;
          bx = b.key;
          sx = s.key;
        }
      }
    }
    if (bx == null || sx == null || best < minCross || best > maxCross) return;
    final B = qs[bx]!, S = qs[sx]!;
    final liq = min(B.askQty * B.ask, S.bidQty * S.bid) * px.q2u(bx, quote);
    if (liq < minLiq) return;
    final w = _wallet(wal, base, bx, sx);
    out.add(CrossOpp(pair, base, bx, sx, B.ask, S.bid, best, liq, B.est || S.est, w.$1, w.$2));
  });
  out.sort((a, b) => b.net.compareTo(a.net));
  return out;
}

/// X/USDT quote for asset [a] (direct, or inverted from USDT/A).
Quote? _usd(Map<String, Quote> m, String a) {
  final q = m['$a/USDT'];
  if (q != null) return q;
  final r = m['USDT/$a'];
  if (r == null) return null;
  // base is USDT, so convert sizes into units of A
  return Quote(1 / r.ask, 1 / r.bid, r.askQty * r.ask, r.bidQty * r.bid, est: r.est);
}

List<TriOpp> scanTri(Spot spot) {
  final out = <TriOpp>[];
  spot.forEach((ex, m) {
    m.forEach((sym, yx) {
      final p = sym.split('/');
      final y = p[0], x = p[1]; // pair Y/X, bridge asset X
      if (x == 'USDT' || stables.contains(x) || stables.contains(y) || x == y) return;
      final xu = _usd(m, x), yu = _usd(m, y);
      if (xu == null || yu == null) return;
      // USDT -> X -> Y -> USDT
      final fwd = yu.bid / (xu.ask * yx.ask);
      // USDT -> Y -> X -> USDT
      final rev = (xu.bid * yx.bid) / yu.ask;
      final isFwd = fwd >= rev;
      final net = max(fwd, rev) * pow(1 - fee, 3) - 1;
      if (net < minTri || net > maxTri) return;
      final yPx = yu.mid;
      final liq = isFwd
          ? [xu.askQty * xu.ask, yx.askQty * yPx, yu.bidQty * yu.bid].reduce(min)
          : [yu.askQty * yu.ask, yx.bidQty * yPx, xu.bidQty * xu.bid].reduce(min);
      if (liq < minLiq) return;
      out.add(TriOpp(ex, isFwd ? 'USDT → $x → $y → USDT' : 'USDT → $y → $x → USDT',
          isFwd ? 'Forward' : 'Reverse', net, liq));
    });
  });
  out.sort((a, b) => b.net.compareTo(a.net));
  return out;
}

List<FundOpp> scanFunding(Map<String, Map<String, double>> f) {
  final by = <String, Map<String, double>>{};
  f.forEach((ex, m) => m.forEach((c, r) => (by[c] ??= <String, double>{})[ex] = r));
  final out = <FundOpp>[];
  by.forEach((coin, rs) {
    final es = rs.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final lo = es.first, hi = es.last;
    final single = es.length < 2;
    final edge = single ? lo.value.abs() : (hi.value - lo.value).abs();
    if (edge < minFund || edge > maxFund) return;
    final strat = single
        ? (lo.value > 0 ? 'SHORT perp on ${lo.key} (+ LONG spot)' : 'LONG perp on ${lo.key} (+ SHORT spot)')
        : 'SHORT ${hi.key} • LONG ${lo.key}';
    out.add(FundOpp(coin, hi.key, hi.value, lo.key, lo.value, edge, single, strat));
  });
  out.sort((a, b) => b.edge.compareTo(a.edge));
  return out;
}