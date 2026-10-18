import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'models.dart';

const exchanges = ['Binance', 'OKX', 'Bybit', 'Bitget', 'KuCoin', 'MEXC', 'Gate.io', 'BingX', 'HTX', 'Whitebit', 'WEEX'];

const okxHost = 'www.okx.cab';

const stables = {
  'USDT', 'USDC', 'DAI', 'BUSD', 'TUSD', 'FDUSD', 'USDD', 'USDP', 'PYUSD',
  'USDE', 'USD1', 'USDJ', 'GUSD', 'LUSD', 'FRAX', 'USDX'
};

final _quotes = <String>[
  'USDT', 'USDC', 'FDUSD', 'BUSD', 'TUSD', 'DAI', 'USDD', 'USDE', 'USD1', 'PYUSD',
  'EUR', 'GBP', 'TRY', 'BRL', 'AUD', 'ARS', 'RUB', 'UAH', 'PLN', 'CZK', 'RON',
  'ZAR', 'NGN', 'JPY', 'MXN', 'COP', 'IDR', 'AED', 'KZT', 'HUF', 'USD',
  'BTC', 'ETH', 'BNB', 'EURI'
]..sort((a, b) => b.length.compareTo(a.length));

String? splitSym(String s) {
  s = s.toUpperCase();
  for (final sep in ['-', '_', '/']) {
    if (s.contains(sep)) {
      final p = s.split(sep);
      return (p.length == 2 && p[0].isNotEmpty && p[1].isNotEmpty) ? '${p[0]}/${p[1]}' : null;
    }
  }
  for (final q in _quotes) {
    if (s.length > q.length && s.endsWith(q)) return '${s.substring(0, s.length - q.length)}/$q';
  }
  return null;
}

String? coinOf(String s) {
  s = s.toUpperCase().replaceAll(RegExp(r'[-_]SWAP$'), '').replaceAll(RegExp(r'[-_/]'), '');
  for (final suf in ['USDTM', 'USDT']) {
    if (s.endsWith(suf) && s.length > suf.length) {
      s = s.substring(0, s.length - suf.length);
      return s == 'XBT' ? 'BTC' : s;
    }
  }
  return null;
}

dynamic _decode(String s) => jsonDecode(s);

Future<dynamic> getJson(String url, {Map<String, String>? h}) async {
  final r = await http.get(Uri.parse(url), headers: h).timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return r.body.length > 50000 ? compute(_decode, r.body) : jsonDecode(r.body);
}

double d(dynamic v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

void _put(Map<String, Quote> m, String sym, double b, double a, double bq, double aq, {bool est = false}) {
  final s = splitSym(sym);
  if (s == null || b <= 0 || a <= 0 || b > a) return;
  m[s] = Quote(b, a, bq, aq, est: est);
}

Future<Map<String, Quote>> _bookTicker(String base) async {
  final j = await getJson('$base/api/v3/ticker/bookTicker') as List;
  final m = <String, Quote>{};
  for (final e in j) {
    _put(m, '${e['symbol']}', d(e['bidPrice']), d(e['askPrice']), d(e['bidQty']), d(e['askQty']));
  }
  return m;
}

final Map<String, Future<Map<String, Quote>> Function()> spotFetchers = {
  'Binance': () => _bookTicker('https://api.binance.com'),
  'MEXC': () => _bookTicker('https://api.mexc.com'),
  'Bybit': () async {
    final j = await getJson('https://api.bybit.com/v5/market/tickers?category=spot');
    final m = <String, Quote>{};
    for (final e in j['result']['list']) {
      _put(m, '${e['symbol']}', d(e['bid1Price']), d(e['ask1Price']), d(e['bid1Size']), d(e['ask1Size']));
    }
    return m;
  },
  'OKX': () async {
    final j = await getJson('https://$okxHost/api/v5/market/tickers?instType=SPOT');
    final m = <String, Quote>{};
    for (final e in j['data']) {
      _put(m, '${e['instId']}', d(e['bidPx']), d(e['askPx']), d(e['bidSz']), d(e['askSz']));
    }
    return m;
  },
  'Bitget': () async {
    final j = await getJson('https://api.bitget.com/api/v2/spot/market/tickers');
    final m = <String, Quote>{};
    for (final e in j['data']) {
      _put(m, '${e['symbol']}', d(e['bidPr']), d(e['askPr']), d(e['bidSz']), d(e['askSz']));
    }
    return m;
  },
  'KuCoin': () async {
    final j = await getJson('https://api.kucoin.com/api/v1/market/allTickers');
    final m = <String, Quote>{};
    for (final e in j['data']['ticker']) {
      final v = d(e['vol']) * 0.001;
      _put(m, '${e['symbol']}', d(e['buy']), d(e['sell']), v, v, est: true);
    }
    return m;
  },
  'Gate.io': () async {
    final j = await getJson('https://api.gateio.ws/api/v4/spot/tickers') as List;
    final m = <String, Quote>{};
    for (final e in j) {
      final v = d(e['base_volume']) * 0.001;
      _put(m, '${e['currency_pair']}', d(e['highest_bid']), d(e['lowest_ask']), v, v, est: true);
    }
    return m;
  },
  'BingX': () async {
    final j = await getJson('https://open-api.bingx.com/openApi/spot/v1/ticker/24hr?timestamp=${DateTime.now().millisecondsSinceEpoch}');
    final m = <String, Quote>{};
    for (final e in j['data']) {
      var bq = d(e['bidQty']), aq = d(e['askQty']);
      final est = bq <= 0 || aq <= 0;
      if (est) bq = aq = d(e['volume']) * 0.001;
      _put(m, '${e['symbol']}', d(e['bidPrice']), d(e['askPrice']), bq, aq, est: est);
    }
    return m;
  },
  'HTX': () async {
    final j = await getJson('https://api.huobi.pro/market/tickers');
    final m = <String, Quote>{};
    for (final e in j['data']) {
      final v = d(e['amount']) * 0.001; 
      _put(m, '${e['symbol']}', d(e['bid']), d(e['ask']), d(e['bidSize']), d(e['askSize']), est: v <= 0);
    }
    return m;
  },
  'Whitebit': () async {
    final j = await getJson('https://whitebit.com/api/v4/public/ticker');
    final m = <String, Quote>{};
    j.forEach((k, v) {
      if (v is Map) {
        final vol = d(v['base_volume']) * 0.001;
        _put(m, k, d(v['highest_bid']), d(v['lowest_ask']), vol, vol, est: true);
      }
    });
    return m;
  },
  'WEEX': () async {
    final j = await getJson('https://api-spot.weex.com/api/v1/market/tickers');
    final m = <String, Quote>{};
    for (final e in j['data']) {
      _put(m, '${e['symbol']}', d(e['bidPrice']), d(e['askPrice']), d(e['bidSize']), d(e['askSize']));
    }
    return m;
  },
};

void _f(Map<String, double> m, dynamic sym, dynamic rate, double hrs) {
  if (sym == null || rate == null) return;
  final c = coinOf(sym.toString());
  if (c == null) return;
  if (hrs <= 0) hrs = 8;
  m[c] = d(rate) * 8 / hrs;
}

Map<String, double>? _binHrs;
DateTime? _binHrsAt;

final Map<String, Future<Map<String, double>> Function()> fundFetchers = {
  'Binance': () async {
    final j = await getJson('https://fapi.binance.com/fapi/v1/premiumIndex') as List;
    if (_binHrs == null || DateTime.now().difference(_binHrsAt!).inMinutes >= 60) {
      final h = <String, double>{};
      try {
        for (final e in await getJson('https://fapi.binance.com/fapi/v1/fundingInfo') as List) {
          h['${e['symbol']}'] = d(e['fundingIntervalHours']);
        }
        _binHrs = h;
        _binHrsAt = DateTime.now();
      } catch (_) {}
    }
    final hrs = _binHrs ?? <String, double>{};
    final m = <String, double>{};
    for (final e in j) {
      _f(m, '${e['symbol']}', e['lastFundingRate'], hrs['${e['symbol']}'] ?? 8);
    }
    return m;
  },
  'Bybit': () async {
    final j = await getJson('https://api.bybit.com/v5/market/tickers?category=linear');
    final m = <String, double>{};
    for (final e in j['result']['list']) {
      _f(m, '${e['symbol']}', e['fundingRate'], d(e['fundingIntervalHour']));
    }
    return m;
  },
  'OKX': () async {
    try {
      final r = await getJson('https://$okxHost/api/v5/public/funding-rate?instId=ANY');
      final bm = <String, double>{};
      for (final e in r['data']) {
        final id = '${e['instId']}';
        if (!id.endsWith('-USDT-SWAP')) continue;
        var hrs = (d(e['nextFundingTime']) - d(e['fundingTime'])) / 3600000;
        if (hrs <= 0 || hrs > 24) hrs = 8;
        _f(bm, id, e['fundingRate'], hrs);
      }
      if (bm.length > 20) return bm;
    } catch (_) {}
    final ins = await getJson('https://$okxHost/api/v5/public/instruments?instType=SWAP');
    final ids = <String>[
      for (final e in ins['data'])
        if ('${e['instId']}'.endsWith('-USDT-SWAP') && e['state'] == 'live') '${e['instId']}'
    ];
    final m = <String, double>{};
    for (var i = 0; i < ids.length; i += 10) {
      final batch = ids.skip(i).take(10);
      await Future.wait(batch.map((id) async {
        try {
          final r = await getJson('https://$okxHost/api/v5/public/funding-rate?instId=$id');
          final e = r['data'][0];
          var hrs = (d(e['nextFundingTime']) - d(e['fundingTime'])) / 3600000;
          if (hrs <= 0 || hrs > 24) hrs = 8;
          _f(m, id, e['fundingRate'], hrs);
        } catch (_) {}
      }));
      await Future.delayed(const Duration(milliseconds: 900));
    }
    if (m.isEmpty) throw Exception('no funding data');
    return m;
  },
  'Bitget': () async {
    final j = await getJson('https://api.bitget.com/api/v2/mix/market/tickers?productType=USDT-FUTURES');
    final m = <String, double>{};
    for (final e in j['data']) {
      _f(m, '${e['symbol']}', e['fundingRate'], 8);
    }
    return m;
  },
  'KuCoin': () async {
    final j = await getJson('https://api-futures.kucoin.com/api/v1/contracts/active');
    final m = <String, double>{};
    for (final e in j['data']) {
      _f(m, '${e['symbol']}', e['fundingFeeRate'], d(e['fundingRateGranularity']) / 3600000);
    }
    return m;
  },
  'MEXC': () async {
    final j = await getJson('https://contract.mexc.com/api/v1/contract/funding_rate');
    final m = <String, double>{};
    for (final e in j['data']) {
      _f(m, '${e['symbol']}', e['fundingRate'], d(e['collectCycle']));
    }
    return m;
  },
  'Gate.io': () async {
    final j = await getJson('https://api.gateio.ws/api/v4/futures/usdt/contracts') as List;
    final m = <String, double>{};
    for (final e in j) {
      _f(m, '${e['name']}', e['funding_rate'], d(e['funding_interval']) / 3600);
    }
    return m;
  },
  'BingX': () async {
    final j = await getJson('https://open-api.bingx.com/openApi/swap/v2/quote/premiumIndex');
    final m = <String, double>{};
    final data = j['data'];
    if (data is List) {
      for (final e in data) {
        _f(m, '${e['symbol']}', e['lastFundingRate'], d(e['fundingIntervalHours']));
      }
    }
    return m;
  },
  'HTX': () async {
    return <String, double>{};
  },
  'Whitebit': () async {
    final j = await getJson('https://whitebit.com/api/v4/public/futures');
    final m = <String, double>{};
    for (final e in j['result']) {
      _f(m, e['ticker'], e['fundingRate'], 8);
    }
    return m;
  },
  'WEEX': () async {
    final j = await getJson('https://api-contract.weex.com/capi/v1/market/tickers');
    final m = <String, double>{};
    for (final e in j['data']) {
      _f(m, e['symbol'], e['fundingRate'], 8);
    }
    return m;
  },
};
