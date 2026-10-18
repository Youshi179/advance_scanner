import 'dart:math';
import 'api.dart';
import 'models.dart';

const fee = 0.0;
const minCross = 0.02, maxCross = 0.20;
const minTri = 0.001, maxTri = 0.20;
const minFund = 0.02, maxFund = 0.40;
const minLiq = 500.0;

typedef Spot = Map<String, Map<String, Quote>>;

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
        final net = (s.value.bid - b.value.ask) / b.value.ask;
        if (net > best) {
          best = net;
          bx = b.key;
          sx = s.key;
        }
      }
    }
    
    if (bx == null || sx == null || best < minCross || best > maxCross) return;
    final B = qs[bx]!, S = qs[sx]!;
    
    final liq = min(B.askQty * B.ask, S.bidQty * S.bid); 
    if (liq < minLiq) return;
    
    final w = _wallet(wal, base, bx, sx);
    out.add(CrossOpp(pair, base, bx, sx, B.ask, S.bid, best, liq, B.est || S.est, w.$1, w.$2));
  });
  out.sort((a, b) => b.net.compareTo(a.net));
  return out;
}

List<TriOpp> scanTri(Spot spot) {
  final out = <TriOpp>[];
  
  spot.forEach((ex, m) {
    for (var p1 in m.entries) {
      final parts1 = p1.key.split('/');
      final a = parts1[0], b = parts1[1];
      if (a == b || (stables.contains(a) && stables.contains(b))) continue;

      final rate1 = p1.value.bid;

      for (var p2 in m.entries) {
        final parts2 = p2.key.split('/');
        String c;
        double rate2;
        
        if (parts2[0] == b) {
          c = parts2[1];
          rate2 = p2.value.bid;
        } else if (parts2[1] == b) {
          c = parts2[0];
          rate2 = 1 / p2.value.ask;
        } else {
          continue;
        }

        if (c == a || c == b || (stables.contains(c) && stables.contains(a))) continue;

        final key3_1 = '$c/$a';
        final key3_2 = '$a/$c';
        double rate3 = 0;
        double liq3 = 0;

        if (m.containsKey(key3_1)) {
          rate3 = m[key3_1]!.bid;
          liq3 = m[key3_1]!.bidQty;
        } else if (m.containsKey(key3_2)) {
          rate3 = 1 / m[key3_2]!.ask;
          liq3 = m[key3_2]!.askQty;
        } else {
          continue;
        }

        final total = rate1 * rate2 * rate3;
        final net = total - 1;

        if (net >= minTri && net <= maxTri) {
          if (a.compareTo(b) < 0 && b.compareTo(c) < 0) {
            final liq = min(p1.value.bidQty * p1.value.bid, min(p2.value.bidQty * p2.value.bid, liq3 * rate3));
            if (liq >= minLiq) {
              out.add(TriOpp(ex, '$a → $b → $c → $a', 'Cycle', net, liq));
            }
          }
        }
      }
    }
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
