class Quote {
  final double bid, ask, bidQty, askQty;
  final bool est; // true when sizes are estimated from 24h volume
  const Quote(this.bid, this.ask, this.bidQty, this.askQty, {this.est = false});
  double get mid => (bid + ask) / 2;
}

/// Wallet status of one coin on one exchange (null = unknown).
class WS {
  final bool? dep, wd;
  const WS(this.dep, this.wd);
}

enum WStatus { ok, blocked, unknown }

class CrossOpp {
  final String pair, base, buyEx, sellEx, wsMsg;
  final double buy, sell, net, liq;
  final bool est;
  final WStatus ws;
  CrossOpp(this.pair, this.base, this.buyEx, this.sellEx, this.buy, this.sell,
      this.net, this.liq, this.est, this.ws, this.wsMsg);
}

class TriOpp {
  final String ex, path, dir;
  final double net, liq;
  TriOpp(this.ex, this.path, this.dir, this.net, this.liq);
}

class FundOpp {
  final String coin, hiEx, loEx, strategy;
  final double hi, lo, edge; // per-8h rates (fractions)
  final bool single;
  FundOpp(this.coin, this.hiEx, this.hi, this.loEx, this.lo, this.edge,
      this.single, this.strategy);
}

class Scan {
  final List<CrossOpp> cross;
  final List<TriOpp> tri;
  final List<FundOpp> fund;
  final int spotOk, fundOk;
  final List<String> errors;
  final DateTime time;
  Scan(this.cross, this.tri, this.fund, this.spotOk, this.fundOk, this.errors,
      this.time);
}