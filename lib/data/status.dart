import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'models.dart';

class Cred {
  final String key, secret, pass;
  const Cred(this.key, this.secret, [this.pass = '']);
}

class WsCoin {
  final bool dep, wd;
  const WsCoin(this.dep, this.wd);
}

/// Secure storage of read-only API keys.
class KeyStore {
  final _s = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<Cred?> load(String ex) async {
    try {
      final k = await _s.read(key: 'key_$ex');
      final s = await _s.read(key: 'secret_$ex');
      if (k == null || s == null || k.isEmpty || s.isEmpty) return null;
      return Cred(k, s, await _s.read(key: 'pass_$ex') ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String ex, Cred c) async {
    await _s.write(key: 'key_$ex', value: c.key.trim());
    await _s.write(key: 'secret_$ex', value: c.secret.trim());
    await _s.write(key: 'pass_$ex', value: c.pass.trim());
  }

  Future<void> remove(String ex) async {
    await _s.delete(key: 'key_$ex');
    await _s.delete(key: 'secret_$ex');
    await _s.delete(key: 'pass_$ex');
  }
}

String _hex(String secret, String msg) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(msg)).toString();

String _b64(String secret, String msg) => base64
    .encode(Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(msg)).bytes);

bool _on(dynamic v) => v == true || v == 1 || '$v' == '1' || '$v' == 'true';

class WalletService {
  static const needKey = ['Binance', 'OKX', 'Bybit', 'MEXC', 'BingX'];
  static const publicEx = ['KuCoin', 'Gate.io', 'Bitget'];
  static const needPass = ['OKX'];

  final keys = KeyStore();
  final Map<String, Map<String, WsCoin>> data = {};
  DateTime? _last;

  /// Refresh wallet data (cached 5 min unless [force]).
  Future<void> refresh(List<String> errors, {bool force = false}) async {
    if (!force &&
        _last != null &&
        DateTime.now().difference(_last!).inMinutes < 5) {
      return;
    }
    _last = DateTime.now();
    await Future.wait(exchanges.map((ex) async {
      try {
        Cred? c;
        if (needKey.contains(ex)) {
          c = await keys.load(ex);
          if (c == null) {
            data.remove(ex);
            return;
          }
        }
        data[ex] = await _fetch(ex, c);
      } catch (e) {
        data.remove(ex);
        errors.add('$ex wallet: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }));
  }

  Future<Map<String, WsCoin>> _fetch(String ex, Cred? c) async {
    switch (ex) {
      case 'Binance':
        return _networkList(await _signed(
            'https://api.binance.com/sapi/v1/capital/config/getall',
            'X-MBX-APIKEY', c!));
      case 'MEXC':
        return _networkList(await _signed(
            'https://api.mexc.com/api/v3/capital/config/getall',
            'X-MEXC-APIKEY', c!));
      case 'BingX':
        final j = await _signed(
            'https://open-api.bingx.com/openApi/wallets/v1/capital/config/getall',
            'X-BX-APIKEY', c!);
        return _networkList(j is Map ? j['data'] : j);
      case 'OKX':
        return _okx(c!);
      case 'Bybit':
        return _bybit(c!);
      case 'KuCoin':
        return _kucoin();
      case 'Gate.io':
        return _gate();
      case 'Bitget':
        return _bitget();
    }
    throw Exception('unsupported');
  }

  Future<dynamic> _signed(String url, String header, Cred c) {
    final q = 'timestamp=${DateTime.now().millisecondsSinceEpoch}&recvWindow=10000';
    return getJson('$url?$q&signature=${_hex(c.secret, q)}',
        headers: {header: c.key});
  }

  void _merge(Map<String, WsCoin> m, String coin, bool dep, bool wd) {
    final k = coin.toUpperCase();
    final o = m[k];
    m[k] = WsCoin((o?.dep ?? false) || dep, (o?.wd ?? false) || wd);
  }

  Map<String, WsCoin> _networkList(dynamic list) {
    final m = <String, WsCoin>{};
    for (final e in (list as List)) {
      var d = false, w = false;
      for (final n in (e['networkList'] as List? ?? [])) {
        d |= _on(n['depositEnable']);
        w |= _on(n['withdrawEnable']);
      }
      _merge(m, e['coin'].toString(), d, w);
    }
    return m;
  }

  Future<Map<String, WsCoin>> _okx(Cred c) async {
    const path = '/api/v5/asset/currencies';
    final now = DateTime.now().toUtc();
    final ts =
        DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch, isUtc: true)
            .toIso8601String();
    final j = await getJson('https://$okxHost$path', headers: {
      'OK-ACCESS-KEY': c.key,
      'OK-ACCESS-SIGN': _b64(c.secret, '${ts}GET$path'),
      'OK-ACCESS-TIMESTAMP': ts,
      'OK-ACCESS-PASSPHRASE': c.pass,
    });
    if (j['code'] != '0') throw Exception('OKX ${j['msg']}');
    final m = <String, WsCoin>{};
    for (final e in j['data']) {
      _merge(m, e['ccy'].toString(), _on(e['canDep']), _on(e['canWd']));
    }
    return m;
  }

  Future<Map<String, WsCoin>> _bybit(Cred c) async {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    const rw = '10000';
    final j = await getJson('https://api.bybit.com/v5/asset/coin/query-info',
        headers: {
          'X-BAPI-API-KEY': c.key,
          'X-BAPI-TIMESTAMP': ts,
          'X-BAPI-RECV-WINDOW': rw,
          'X-BAPI-SIGN': _hex(c.secret, '$ts${c.key}$rw'),
        });
    if (j['retCode'] != 0) throw Exception('Bybit ${j['retMsg']}');
    final m = <String, WsCoin>{};
    for (final e in j['result']['rows']) {
      var d = false, w = false;
      for (final ch in (e['chains'] as List? ?? [])) {
        d |= _on(ch['chainDeposit']);
        w |= _on(ch['chainWithdraw']);
      }
      _merge(m, e['coin'].toString(), d, w);
    }
    return m;
  }

  Future<Map<String, WsCoin>> _kucoin() async {
    final j = await getJson('https://api.kucoin.com/api/v3/currencies');
    final m = <String, WsCoin>{};
    for (final e in j['data']) {
      var d = false, w = false;
      for (final ch in (e['chains'] as List? ?? [])) {
        d |= _on(ch['isDepositEnabled']);
        w |= _on(ch['isWithdrawEnabled']);
      }
      _merge(m, e['currency'].toString(), d, w);
    }
    return m;
  }

  Future<Map<String, WsCoin>> _gate() async {
    final j = await getJson('https://api.gateio.ws/api/v4/spot/currencies');
    final m = <String, WsCoin>{};
    for (final e in (j as List)) {
      final delisted = _on(e['delisted']);
      _merge(m, e['currency'].toString(),
          !delisted && !_on(e['deposit_disabled']),
          !delisted && !_on(e['withdraw_disabled']));
    }
    return m;
  }

  Future<Map<String, WsCoin>> _bitget() async {
    final j = await getJson('https://api.bitget.com/api/v2/spot/public/coins');
    final m = <String, WsCoin>{};
    for (final e in j['data']) {
      var d = false, w = false;
      for (final ch in (e['chains'] as List? ?? [])) {
        d |= _on(ch['rechargeable']);
        w |= _on(ch['withdrawable']);
      }
      _merge(m, e['coin'].toString(), d, w);
    }
    return m;
  }

  bool? _flag(String ex, String coin, {required bool withdraw}) {
    final c = data[ex]?[coin.toUpperCase()];
    if (c == null) return null;
    return withdraw ? c.wd : c.dep;
  }

  /// Buy exchange must allow withdraw; sell exchange must allow deposit.
  WS check(String buyEx, String sellEx, String coin) {
    final wd = _flag(buyEx, coin, withdraw: true);
    final dp = _flag(sellEx, coin, withdraw: false);
    if (wd == false || dp == false) {
      final bad = [
        if (wd == false) '$buyEx withdraw closed',
        if (dp == false) '$sellEx deposit closed',
      ];
      return WS(WsState.blocked, bad.join(' • '));
    }
    if (wd == true && dp == true) {
      return WS(WsState.ok, 'Withdraw $buyEx ✓  •  Deposit $sellEx ✓');
    }
    final noKey = [
      for (final e in [buyEx, sellEx])
        if (needKey.contains(e) && !data.containsKey(e)) e
    ];
    if (noKey.isNotEmpty) {
      return WS(WsState.unknown, 'No API key: ${noKey.toSet().join(', ')}');
    }
    return const WS(WsState.unknown, 'Coin not found in wallet data');
  }
}
