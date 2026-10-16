/// Best bid/ask for one pair on one exchange. [est] = quantities are estimated
/// (exchange doesn't publish top-of-book size) from 24h volume.
class Quote {
  final double bid, ask, bidQty, askQty;
  final bool est;
  const Quote(this.bid, this.ask, this.bidQty, this.askQty, {this.est = false});
}

/// Funding rate for one perp: [rate] per funding interval, [hours] interval.
class FR {
  final double rate;
  final double hours;
  const FR(this.rate, this.hours);
  double get per8 => rate * 8 / (hours <= 0 ? 8 : hours);
}

enum WsState { ok, blocked, unknown }

/// Wallet status (deposit/withdraw verification).
class WS {
  final WsState state;
  final String msg;
  const WS(this.state, this.msg);
  String get icon => switch (state) {
        WsState.ok => '🟢',
        WsState.blocked => '🔴',
        WsState.unknown => '🟡',
      };
}

class CrossOpp {
  final String pair, base, quote, buyEx, sellEx;
  final double buyAsk, sellBid, gross, net, liq;
  final bool est;
  final WS ws;
  const CrossOpp({
    required this.pair,
    required this.base,
    required this.quote,
    required this.buyEx,
    required this.sellEx,
    required this.buyAsk,
    required this.sellBid,
    required this.gross,
    required this.net,
    required this.liq,
    required this.est,
    required this.ws,
  });
}

class TriOpp {
  final String exchange, x, y, path;
  final bool forward, est;
  final double net, liq;
  const TriOpp({
    required this.exchange,
    required this.x,
    required this.y,
    required this.path,
    required this.forward,
    required this.net,
    required this.liq,
    required this.est,
  });
}

class FundOpp {
  final String coin, hiEx, loEx;
  final double hiRate, loRate, edge; // per 8h
  final bool single;
  const FundOpp({
    required this.coin,
    required this.hiEx,
    required this.hiRate,
    required this.loEx,
    required this.loRate,
    required this.edge,
    required this.single,
  });

  String get strategy {
    if (!single) return 'SHORT $hiEx  •  LONG $loEx';
    return hiRate > 0
        ? 'SHORT perp $hiEx  +  LONG spot'
        : 'LONG perp $hiEx  +  SHORT spot/margin';
  }
}

class Scan {
  final List<CrossOpp> cross;
  final List<TriOpp> tri;
  final List<FundOpp> fund;
  final int spotOk, fundOk, total;
  final List<String> errors;
  final DateTime time;
  const Scan({
    required this.cross,
    required this.tri,
    required this.fund,
    required this.spotOk,
    required this.fundOk,
    required this.total,
    required this.errors,
    required this.time,
  });
}
