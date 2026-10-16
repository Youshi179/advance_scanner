import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'models.dart';

const timeout = Duration(seconds: 20);
const okxHost = 'www.okx.cab'; // .cab avoids regional blocks of .com

const exchanges = [
  'Binance', 'OKX', 'Bybit', 'Bitget', 'KuCoin', 'MEXC', 'Gate.io', 'BingX'
];

Future<dynamic> getJson(String url, {Map<String, String>? headers}) async {
  final r = await http.get(Uri.parse(url), headers: headers).timeout(timeout);
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(r.body);
}

double dbl(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

// ---------------------------------------------------------------- symbols

/// Quote assets, longest/most specific first. Includes fiat.
const _quotes = [
  'FDUSD', 'USDT', 'USDC', 'USDD', 'TUSD', 'BUSD', 'USDP', 'DAI',
  'EUR', 'GBP', 'TRY', 'BRL', 'AUD', 'RUB', 'UAH', 'ARS', 'PLN', 'RON',
  'CZK', 'JPY', 'ZAR', 'MXN', 'COP', 'NGN', 'IDR', 'USD',
  'BTC', 'ETH', 'BNB',
];

(String, String)? splitSym(String s) {
  for (final q in _quotes) {
    if (s.length > q.length && s.endsWith(q)) {
      return (s.substring(0, s.length - q.length), q);
    }
  }
  return null;
}

String normCoin(String c) {
  c = c.toUpperCase();
  if (c == 'XBT') return 'BTC';
  final m = RegExp(r'^(1000000|10000|1000)(?=[A-Z])').firstMatch(c);
  return m == null ? c : c.substring(m.end);
}

// ------------------------------------------------------------------- spot

void _put(Map<String, Quote> out, String base, String quote, double bid,
    double ask, double bq, double aq,
    {bool est = false}) {
  if (base.isEmpty || quote.isEmpty) return;
  if (bid <= 0 || ask <= 0 || bid > ask) return;
  if (bq <= 0 || aq <= 0) return;
  out['${base.toUpperCase()}/${quote.toUpperCase()}'] =
      Quote(bid, ask, bq, aq, est: est);
}

Future<Map<String, Quote>> _bookTicker(String url) async {
  final j = await getJson(url) as List;
  final out = <String, Quote>{};
  for (final e in j) {
    final s = splitSym(e['symbol'].toString());
    if (s == null) continue;
    _put(out, s.$1, s.$2, dbl(e['bidPrice']), dbl(e['askPrice']),
        dbl(e['bidQty']), dbl(e['askQty']));
  }
  return out;
}

Future<Map<String, Quote>> spotBinance() async {
  try {
    return await _bookTicker(
        'https://data-api.binance.vision/api/v3/ticker/bookTicker');
  } catch (_) {
    return _bookTicker('https://api.binance.com/api/v3/ticker/bookTicker');
  }
}

Future<Map<String, Quote>> spotMexc() =>
    _bookTicker('https://api.mexc.com/api/v3/ticker/bookTicker');

Future<Map<String, Quote>> spotBybit() async {
  final j = await getJson('https://api.bybit.com/v5/market/tickers?category=spot');
  final out = <String, Quote>{};
  for (final e in j['result']['list']) {
    final s = splitSym(e['symbol'].toString());
    if (s == null) continue;
    _put(out, s.$1, s.$2, dbl(e['bid1Price']), dbl(e['ask1Price']),
        dbl(e['bid1Size']), dbl(e['ask1Size']));
  }
  return out;
}

Future<Map<String, Quote>> spotOkx() async {
  final j = await getJson('https://$okxHost/api/v5/market/tickers?instType=SPOT');
  final out = <String, Quote>{};
  for (final e in j['data']) {
    final p = e['instId'].toString().split('-');
    if (p.length != 2) continue;
    _put(out, p[0], p[1], dbl(e['bidPx']), dbl(e['askPx']), dbl(e['bidSz']),
        dbl(e['askSz']));
  }
  return out;
}

Future<Map<String, Quote>> spotBitget() async {
  final j = await getJson('https://api.bitget.com/api/v2/spot/market/tickers');
  final out = <String, Quote>{};
  for (final e in j['data']) {
    final s = splitSym(e['symbol'].toString());
    if (s == null) continue;
    _put(out, s.$1, s.$2, dbl(e['bidPr']), dbl(e['askPr']), dbl(e['bidSz']),
        dbl(e['askSz']));
  }
  return out;
}

/// KuCoin: no top-of-book size in allTickers -> estimate from 24h base volume.
Future<Map<String, Quote>> spotKucoin() async {
  final j = await getJson('https://api.kucoin.com/api/v1/market/allTickers');
  final out = <String, Quote>{};
  for (final e in j['data']['ticker']) {
    final p = e['symbol'].toString().split('-');
    if (p.length != 2) continue;
    final q = dbl(e['vol']) / 288; // ~5 min of volume
    _put(out, p[0], p[1], dbl(e['buy']), dbl(e['sell']), q, q, est: true);
  }
  return out;
}

/// Gate: tickers carry no book size -> estimate from 24h base volume.
Future<Map<String, Quote>> spotGate() async {
  final j = await getJson('https://api.gateio.ws/api/v4/spot/tickers');
  final out = <String, Quote>{};
  for (final e in j) {
    final p = e['currency_pair'].toString().split('_');
    if (p.length != 2) continue;
    final q = dbl(e['base_volume']) / 288;
    _put(out, p[0], p[1], dbl(e['highest_bid']), dbl(e['lowest_ask']), q, q,
        est: true);
  }
  return out;
}

Future<Map<String, Quote>> spotBingx() async {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final j = await getJson(
      'https://open-api.bingx.com/openApi/spot/v1/ticker/24hr?timestamp=$ts');
  final out = <String, Quote>{};
  for (final e in j['data']) {
    final p = e['symbol'].toString().split('-');
    if (p.length != 2) continue;
    _put(out, p[0], p[1], dbl(e['bidPrice']), dbl(e['askPrice']),
        dbl(e['bidVolume']), dbl(e['askVolume']));
  }
  return out;
}

final Map<String, Future<Map<String, Quote>> Function()> spotFetchers = {
  'Binance': spotBinance,
  'OKX': spotOkx,
  'Bybit': spotBybit,
  'Bitget': spotBitget,
  'KuCoin': spotKucoin,
  'MEXC': spotMexc,
  'Gate.io': spotGate,
  'BingX': spotBingx,
};

// ---------------------------------------------------------------- funding

Future<Map<String, FR>> fundBinance() async {
  final res = await Future.wait([
    getJson('https://fapi.binance.com/fapi/v1/premiumIndex'),
    getJson('https://fapi.binance.com/fapi/v1/fundingInfo')
        .catchError((_) => <dynamic>[]),
  ]);
  final hours = <String, double>{
    for (final e in (res[1] as List))
      e['symbol'].toString(): dbl(e['fundingIntervalHours'])
  };
  final out = <String, FR>{};
  for (final e in (res[0] as List)) {
    final s = e['symbol'].toString();
    if (!s.endsWith('USDT') || e['lastFundingRate'] == null) continue;
    final h = hours[s] ?? 8;
    out[normCoin(s.substring(0, s.length - 4))] =
        FR(dbl(e['lastFundingRate']), h > 0 ? h : 8);
  }
  return out;
}

List<String>? _okxIds;

/// OKX has no bulk funding endpoint: list instruments, then query each one
/// (batched to respect the 20 req / 2s limit).
Future<Map<String, FR>> fundOkx() async {
  if (_okxIds == null) {
    final inst =
        await getJson('https://$okxHost/api/v5/public/instruments?instType=SWAP');
    _okxIds = [
      for (final e in inst['data'])
        if (e['instId'].toString().endsWith('-USDT-SWAP') &&
            (e['state'] == null || e['state'] == 'live'))
          e['instId'].toString()
    ];
  }
  final ids = _okxIds!;
  final out = <String, FR>{};
  for (var i = 0; i < ids.length; i += 10) {
    final chunk = ids.sublist(i, min(i + 10, ids.length));
    await Future.wait(chunk.map((id) async {
      try {
        final j = await getJson(
            'https://$okxHost/api/v5/public/funding-rate?instId=$id');
        final d = j['data'][0];
        final ft = dbl(d['fundingTime']), nt = dbl(d['nextFundingTime']);
        var h = (nt - ft) / 3600000;
        if (h <= 0 || h > 24) h = 8;
        out[normCoin(id.split('-')[0])] = FR(dbl(d['fundingRate']), h);
      } catch (_) {/* skip this instrument */}
    }));
    await Future.delayed(const Duration(milliseconds: 1050));
  }
  if (out.isEmpty) throw Exception('no funding data');
  return out;
}

Future<Map<String, FR>> fundBybit() async {
  final j =
      await getJson('https://api.bybit.com/v5/market/tickers?category=linear');
  final out = <String, FR>{};
  for (final e in j['result']['list']) {
    final s = e['symbol'].toString();
    if (!s.endsWith('USDT') || (e['fundingRate'] ?? '') == '') continue;
    final h = dbl(e['fundingIntervalHour']);
    out[normCoin(s.substring(0, s.length - 4))] =
        FR(dbl(e['fundingRate']), h > 0 ? h : 8);
  }
  return out;
}

Future<Map<String, FR>> fundBitget() async {
  final j = await getJson(
      'https://api.bitget.com/api/v2/mix/market/tickers?productType=USDT-FUTURES');
  final out = <String, FR>{};
  for (final e in j['data']) {
    final s = e['symbol'].toString();
    if (!s.endsWith('USDT') || (e['fundingRate'] ?? '') == '') continue;
    out[normCoin(s.substring(0, s.length - 4))] = FR(dbl(e['fundingRate']), 8);
  }
  return out;
}

Future<Map<String, FR>> fundKucoin() async {
  final j = await getJson('https://api-futures.kucoin.com/api/v1/contracts/active');
  final out = <String, FR>{};
  for (final e in j['data']) {
    if (e['settleCurrency'] != 'USDT' || e['fundingFeeRate'] == null) continue;
    var h = dbl(e['fundingRateGranularity']) / 3600000;
    if (h <= 0) h = 8;
    out[normCoin(e['baseCurrency'].toString())] =
        FR(dbl(e['fundingFeeRate']), h);
  }
  return out;
}

Future<Map<String, FR>> fundMexc() async {
  final j = await getJson('https://contract.mexc.com/api/v1/contract/funding_rate');
  final out = <String, FR>{};
  for (final e in j['data']) {
    final s = e['symbol'].toString();
    if (!s.endsWith('_USDT')) continue;
    final h = dbl(e['collectCycle']);
    out[normCoin(s.split('_')[0])] = FR(dbl(e['fundingRate']), h > 0 ? h : 8);
  }
  return out;
}

Future<Map<String, FR>> fundGate() async {
  final j = await getJson('https://api.gateio.ws/api/v4/futures/usdt/contracts');
  final out = <String, FR>{};
  for (final e in j) {
    final n = e['name'].toString();
    if (!n.endsWith('_USDT') || e['funding_rate'] == null) continue;
    final h = dbl(e['funding_interval']) / 3600;
    out[normCoin(n.split('_')[0])] = FR(dbl(e['funding_rate']), h > 0 ? h : 8);
  }
  return out;
}

Future<Map<String, FR>> fundBingx() async {
  final j = await getJson(
      'https://open-api.bingx.com/openApi/swap/v2/quote/premiumIndex');
  final out = <String, FR>{};
  final data = j['data'];
  for (final e in (data is List ? data : [data])) {
    final s = e['symbol'].toString();
    if (!s.endsWith('-USDT') || e['lastFundingRate'] == null) continue;
    final h = dbl(e['fundingIntervalHours']);
    out[normCoin(s.split('-')[0])] =
        FR(dbl(e['lastFundingRate']), h > 0 ? h : 8);
  }
  return out;
}

final Map<String, Future<Map<String, FR>> Function()> fundFetchers = {
  'Binance': fundBinance,
  'OKX': fundOkx,
  'Bybit': fundBybit,
  'Bitget': fundBitget,
  'KuCoin': fundKucoin,
  'MEXC': fundMexc,
  'Gate.io': fundGate,
  'BingX': fundBingx,
};
