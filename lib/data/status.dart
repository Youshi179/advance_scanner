import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'models.dart';

const keyedExchanges = ['Binance', 'OKX', 'Bybit', 'MEXC', 'BingX', 'HTX', 'Whitebit', 'WEEX'];
const publicWalletExchanges = ['KuCoin', 'Gate.io', 'Bitget'];

class Creds {
  final String key, secret, pass;
  const Creds(this.key, this.secret, [this.pass = '']);
}

class KeyStore {
  static const _s = FlutterSecureStorage();
  static Future<Creds?> load(String ex) async {
    final k = await _s.read(key: 'k_$ex'), s = await _s.read(key: 's_$ex');
    if (k == null || s == null || k.isEmpty || s.isEmpty) return null;
    return Creds(k, s, await _s.read(key: 'p_$ex') ?? '');
  }

  static Future<void> save(String ex, Creds c) async {
    await _s.write(key: 'k_$ex', value: c.key.trim());
    await _s.write(key: 's_$ex', value: c.secret.trim());
    await _s.write(key: 'p_$ex', value: c.pass.trim());
  }

  static Future<void> remove(String ex) async {
    for (final p in ['k_', 's_', 'p_']) {
      await _s.delete(key: '$p$ex');
    }
  }
}

bool _b(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';
String _hex(String k, String m) => Hmac(sha256, utf8.encode(k)).convert(utf8.encode(m)).toString();
String _b64(String k, String m) => base64.encode(Hmac(sha256, utf8.encode(k)).convert(utf8.encode(m)).bytes);

void _merge(Map<String, WS> m, String coin, bool dep, bool wd) {
  final o = m[coin];
  m[coin] = WS((o?.dep ?? false) || dep, (o?.wd ?? false) || wd); 
}

Future<dynamic> _qs(String url, String hdr, Creds c) {
  final q = 'timestamp=${DateTime.now().millisecondsSinceEpoch}&recvWindow=10000';
  return getJson('$url?$q&signature=${_hex(c.secret, q)}', h: {hdr: c.key});
}

Map<String, WS> _netList(dynamic j) {
  final m = <String, WS>{};
  if (j is! List) return m;
  for (final e in j) {
    final nets = (e['networkList'] as List?) ?? [];
    _merge(m, '${e['coin']}'.toUpperCase(), nets.any((n) => _b(n['depositEnable'])), nets.any((n) => _b(n['withdrawEnable'])));
  }
  return m;
}

Future<Map<String, WS>?> fetchWallet(String ex) async {
  Creds? c;
  if (keyedExchanges.contains(ex)) {
    c = await KeyStore.load(ex);
    if (c == null) return null; 
  }
  final m = <String, WS>{};
  
  try {
    switch (ex) {
      case 'Binance':
        return _netList(await _qs('https://api.binance.com/sapi/v1/capital/config/getall', 'X-MBX-APIKEY', c!));
      case 'MEXC':
        return _netList(await _qs('https://api.mexc.com/api/v3/capital/config/getall', 'X-MEXC-APIKEY', c!));
      case 'BingX':
        final j = await _qs('https://open-api.bingx.com/openApi/wallets/v1/capital/config/getall', 'X-BX-APIKEY', c!);
        return _netList(j['data']);
      case 'OKX':
        const path = '/api/v5/asset/currencies';
        final ts = '${DateTime.now().toUtc().toIso8601String().substring(0, 23)}Z';
        final j = await getJson('https://$okxHost$path', h: {
          'OK-ACCESS-KEY': c!.key,
          'OK-ACCESS-SIGN': _b64(c.secret, '${ts}GET$path'),
          'OK-ACCESS-TIMESTAMP': ts,
          'OK-ACCESS-PASSPHRASE': c.pass,
        });
        if ('${j['code']}' != '0') throw Exception('OKX ${j['msg']}');
        for (final e in j['data']) {
          _merge(m, '${e['ccy']}'.toUpperCase(), _b(e['canDep']), _b(e['canWd']));
        }
        return m;
      case 'Bybit':
        final ts = '${DateTime.now().millisecondsSinceEpoch}';
        final j = await getJson('https://api.bybit.com/v5/asset/coin/query-info', h: {
          'X-BAPI-API-KEY': c!.key,
          'X-BAPI-TIMESTAMP': ts,
          'X-BAPI-RECV-WINDOW': '10000',
          'X-BAPI-SIGN': _hex(c.secret, '$ts${c.key}10000'),
        });
        if (j['retCode'] != 0) throw Exception('Bybit ${j['retMsg']}');
        for (final e in j['result']['rows']) {
          final ch = (e['chains'] as List?) ?? [];
          _merge(m, '${e['coin']}'.toUpperCase(), ch.any((x) => _b(x['chainDeposit'])), ch.any((x) => _b(x['chainWithdraw'])));
        }
        return m;
      case 'KuCoin':
        final j = await getJson('https://api.kucoin.com/api/v3/currencies');
        for (final e in j['data']) {
          final ch = (e['chains'] as List?) ?? [];
          _merge(m, '${e['currency']}'.toUpperCase(), ch.any((x) => _b(x['isDepositEnabled'])), ch.any((x) => _b(x['isWithdrawEnabled'])));
        }
        return m;
      case 'Gate.io':
        final j = await getJson('https://api.gateio.ws/api/v4/spot/currencies') as List;
        for (final e in j) {
          _merge(m, '${e['currency']}'.toUpperCase(), !_b(e['deposit_disabled']), !_b(e['withdraw_disabled']));
        }
        return m;
      case 'Bitget':
        final j = await getJson('https://api.bitget.com/api/v2/spot/public/coins');
        for (final e in j['data']) {
          final ch = (e['chains'] as List?) ?? [];
          _merge(m, '${e['coin']}'.toUpperCase(), ch.any((x) => _b(x['rechargeable'])), ch.any((x) => _b(x['withdrawable'])));
        }
        return m;
      case 'HTX':
      case 'Whitebit':
      case 'WEEX':
        return null; 
    }
  } catch (e) {
    return null; 
  }
  return null;
}
