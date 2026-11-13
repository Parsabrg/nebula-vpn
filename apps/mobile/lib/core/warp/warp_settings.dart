import 'dart:convert';
import 'dart:io';

/// Cloudflare WARP through Aether (patterniha/Aether, AGPL-3.0), run as a
/// child process that serves a local SOCKS5 proxy. Two uses:
///
/// - WARP mode: the tunnel's traffic leaves through Cloudflare. No server of
///   ours, no account; Cloudflare's free WARP service carries it.
/// - [WarpSettings.throughWarp]: a Nebula server is reached *through* WARP,
///   so the network only ever sees Cloudflare, while the exit, the account
///   and its limits stay ours. Measured 2026-11-13 on the owner's home line,
///   where the server's own address is throttled: 2.6-2.9 MB/s, exit DE.
///
/// MASQUE over HTTP/2 is the default because it is what got through on the
/// owner's line (3-4 MB/s, 2026-11-13) while WireGuard and HTTP/3 did not;
/// Aether's own default is HTTP/3.

enum WarpProtocol {
  masque('masque'),
  wireguard('wg'),

  /// WireGuard carried inside MASQUE (Aether's `gool`): another exit address.
  wgOverMasque('gool'),

  /// WireGuard inside WireGuard, the older gool.
  warpInWarp('gool'),

  /// MASQUE inside MASQUE: another exit address over one carrier.
  masqueInMasque('mim');

  const WarpProtocol(this.core);

  /// The word Aether's `--protocol` takes.
  final String core;

  /// Carried by MASQUE, so the MASQUE transport, server name and
  /// fragmenting apply.
  bool get overMasque =>
      this == masque || this == wgOverMasque || this == masqueInMasque;
}

enum WarpTransport {
  /// TCP 443: survives networks that drop QUIC.
  http2,

  /// QUIC on UDP.
  http3,
}

enum WarpScan { turbo, balanced, thorough, verified, ironclad }

/// Aether's `--noize` profiles; [auto] leaves the choice to Aether (firewall
/// over MASQUE, balanced for WireGuard).
enum WarpObfuscation { auto, off, light, firewall, balanced, gfw, aggressive }

enum WarpIpVersion {
  v4('v4'),
  v6('v6'),
  both('both');

  const WarpIpVersion(this.core);
  final String core;
}

/// The TLS ClientHello of Aether's handshakes, after a real client's.
/// Ported from PattNG's AetherFingerprint (patterniha/PattNG, GPL-3.0),
/// which documents each capture. On Irancell, the maker advises one that is
/// not Chrome.
enum WarpFingerprint {
  chrome(
    ciphers: 'ALL:!aPSK:!ECDSA+SHA1:!3DES',
    grease: true,
    groups: 'X25519MLKEM768:X25519:P-256:P-384',
    sigalgs: 'mldsa44:mldsa65:mldsa87:$_chromeEightSigalgs',
    greaseSigalgs: true,
    certCompression: 'brotli',
    alps: 'new',
    trustAnchors: _chromeTrustAnchors,
    serverPadding: 6000,
    echGrease: true,
  ),
  chrome120(
    ciphers: 'ALL:!aPSK:!ECDSA+SHA1:!3DES',
    grease: true,
    groups: 'X25519:P-256:P-384',
    sigalgs: _chromeEightSigalgs,
    certCompression: 'brotli',
    alps: 'old',
    echGrease: true,
  ),
  firefox(
    ciphers:
        'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:'
        'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:'
        'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:'
        'ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:'
        'AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA:AES256-SHA',
    grease: false,
    groups: 'X25519MLKEM768:X25519:P-256:P-384:P-521',
    sigalgs:
        'ecdsa_secp256r1_sha256:ecdsa_secp384r1_sha384:ecdsa_secp521r1_sha512:'
        'rsa_pss_rsae_sha256:rsa_pss_rsae_sha384:rsa_pss_rsae_sha512:'
        'rsa_pkcs1_sha256:rsa_pkcs1_sha384:rsa_pkcs1_sha512:ecdsa_sha1:'
        'rsa_pkcs1_sha1',
    tls13Ciphers:
        'TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:'
        'TLS_AES_256_GCM_SHA384',
    keyShares: 'X25519MLKEM768:X25519:P-256',
    certCompression: 'zlib:brotli:zstd',
    echGrease: true,
    sessionTicket: false,
    permuteExtensions: false,
  ),
  semiPython(
    ciphers:
        'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:'
        'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:'
        'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:'
        'ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:'
        'ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256',
    grease: false,
    groups: 'X25519MLKEM768:X25519:P-256:P-384:P-521',
    sigalgs:
        'mldsa65:mldsa87:mldsa44:ecdsa_secp256r1_sha256:ecdsa_secp384r1_sha384:'
        'ecdsa_secp521r1_sha512:ed25519:rsa_pss_rsae_sha256:'
        'rsa_pss_rsae_sha384:rsa_pss_rsae_sha512:rsa_pkcs1_sha256:'
        'rsa_pkcs1_sha384:rsa_pkcs1_sha512',
    tls13Ciphers:
        'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:'
        'TLS_AES_128_GCM_SHA256',
    ocspStapling: false,
    sct: false,
    permuteExtensions: false,
  ),
  go(
    ciphers:
        'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:'
        'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:'
        'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:'
        'ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:'
        'ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA',
    grease: false,
    groups: 'X25519MLKEM768:X25519:P-256:P-384:P-521',
    sigalgs:
        'mldsa44:mldsa65:mldsa87:rsa_pss_rsae_sha256:ecdsa_secp256r1_sha256:'
        'ed25519:rsa_pss_rsae_sha384:rsa_pss_rsae_sha512:rsa_pkcs1_sha256:'
        'rsa_pkcs1_sha384:rsa_pkcs1_sha512:ecdsa_secp384r1_sha384:'
        'ecdsa_secp521r1_sha512',
    sessionTicket: false,
    permuteExtensions: false,
  );

  const WarpFingerprint({
    required this.ciphers,
    required this.grease,
    required this.groups,
    required this.sigalgs,
    this.tls13Ciphers,
    this.keyShares,
    this.greaseSigalgs = false,
    this.certCompression,
    this.alps,
    this.trustAnchors,
    this.serverPadding,
    this.echGrease = false,
    this.ocspStapling = true,
    this.sct = true,
    this.sessionTicket = true,
    this.permuteExtensions = true,
  });

  final String ciphers;
  final bool grease;
  final String groups;
  final String sigalgs;
  final String? tls13Ciphers;
  final String? keyShares;
  final bool greaseSigalgs;
  final String? certCompression;
  final String? alps;
  final String? trustAnchors;
  final int? serverPadding;
  final bool echGrease;
  final bool ocspStapling;
  final bool sct;
  final bool sessionTicket;
  final bool permuteExtensions;

  List<String> get arguments => <String>[
    '--tls-ciphers',
    ciphers,
    if (tls13Ciphers != null) ...<String>['--tls13-ciphers', tls13Ciphers!],
    '--tls-groups',
    groups,
    if (keyShares != null) ...<String>['--tls-key-shares', keyShares!],
    '--tls-sigalgs',
    sigalgs,
    if (certCompression != null) ...<String>[
      '--tls-cert-compression',
      certCompression!,
    ],
    if (alps != null) ...<String>['--tls-alps', alps!],
    if (trustAnchors != null) ...<String>['--tls-trust-anchors', trustAnchors!],
    if (serverPadding != null) ...<String>[
      '--tls-server-padding',
      '$serverPadding',
    ],
    if (!grease) '--disable-grease',
    if (greaseSigalgs) '--enable-grease-sigalgs',
    if (echGrease) '--enable-ech-grease',
    if (!ocspStapling) '--disable-ocsp-stapling',
    if (!sct) '--disable-sct',
    if (!sessionTicket) '--disable-session-ticket',
    if (!permuteExtensions) '--disable-extension-permutation',
  ];
}

const String _chromeEightSigalgs =
    'ecdsa_secp256r1_sha256:rsa_pss_rsae_sha256:rsa_pkcs1_sha256:'
    'ecdsa_secp384r1_sha384:rsa_pss_rsae_sha384:rsa_pkcs1_sha384:'
    'rsa_pss_rsae_sha512:rsa_pkcs1_sha512';

const String _chromeTrustAnchors =
    '44947.2.1:44947.2.6:44947.2.13:44947.2.14:44947.2.15:44947.2.18:'
    '44947.2.19:44947.2.20:52580.200109.1.7:52580.200109.1.8:'
    '52580.200109.1.9:52580.200109.1.10:52580.200109.1.11:52580.200109.1.12:'
    '52580.200109.1.13:52580.200109.1.18:52580.200109.1.19:11129.9.1:'
    '11129.9.4:11129.9.5:11129.9.6:11129.9.7:11129.9.8:11129.9.10:'
    '11129.9.11:11129.9.12:11129.9.13:11129.9.15';

const String defaultMasqueSni = 'www.cloudflare.com';

/// Where the app carries Aether: Android so far (the desktop runtimes
/// do not bundle it yet).
bool get warpSupported => Platform.isAndroid;

class WarpSettings {
  const WarpSettings({
    this.protocol = WarpProtocol.masque,
    this.transport = WarpTransport.http2,
    this.scan = WarpScan.balanced,
    this.obfuscation = WarpObfuscation.auto,
    this.fingerprint = WarpFingerprint.chrome,
    this.masqueSni = defaultMasqueSni,
    this.fragment = false,
    this.ech = false,
    this.ipVersion = WarpIpVersion.v4,
    this.endpoint,
    this.quickReconnect = true,
    this.throughWarp = false,
    this.identity = 0,
  });

  final WarpProtocol protocol;
  final WarpTransport transport;
  final WarpScan scan;
  final WarpObfuscation obfuscation;
  final WarpFingerprint fingerprint;

  /// The name MASQUE's TLS handshake carries (the HTTP host stays
  /// Cloudflare's own).
  final String masqueSni;

  /// Split the TLS ClientHello (MASQUE over HTTP/2, and the WARP API calls).
  final bool fragment;

  /// Encrypted Client Hello: hides the server name. Without a usable key
  /// Aether does not connect at all rather than send it in the clear.
  final bool ech;
  final WarpIpVersion ipVersion;

  /// A fixed WARP edge (`ip:port`); null scans for one.
  final String? endpoint;

  /// Reuse the last edge that worked instead of scanning again.
  final bool quickReconnect;

  /// Reach Nebula servers through WARP.
  final bool throughWarp;

  /// Which WARP keys are used: raised by "Get new WARP keys", so the next
  /// connection registers new ones under new file names.
  final int identity;

  static const WarpSettings defaults = WarpSettings();

  WarpSettings copyWith({
    WarpProtocol? protocol,
    WarpTransport? transport,
    WarpScan? scan,
    WarpObfuscation? obfuscation,
    WarpFingerprint? fingerprint,
    String? masqueSni,
    bool? fragment,
    bool? ech,
    WarpIpVersion? ipVersion,
    String? Function()? endpoint,
    bool? quickReconnect,
    bool? throughWarp,
    int? identity,
  }) => WarpSettings(
    protocol: protocol ?? this.protocol,
    transport: transport ?? this.transport,
    scan: scan ?? this.scan,
    obfuscation: obfuscation ?? this.obfuscation,
    fingerprint: fingerprint ?? this.fingerprint,
    masqueSni: masqueSni ?? this.masqueSni,
    fragment: fragment ?? this.fragment,
    ech: ech ?? this.ech,
    ipVersion: ipVersion ?? this.ipVersion,
    endpoint: endpoint == null ? this.endpoint : endpoint(),
    quickReconnect: quickReconnect ?? this.quickReconnect,
    throughWarp: throughWarp ?? this.throughWarp,
    identity: identity ?? this.identity,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol.name,
    'transport': transport.name,
    'scan': scan.name,
    'obfuscation': obfuscation.name,
    'fingerprint': fingerprint.name,
    'masqueSni': masqueSni,
    'fragment': fragment,
    'ech': ech,
    'ipVersion': ipVersion.name,
    'endpoint': endpoint,
    'quickReconnect': quickReconnect,
    'throughWarp': throughWarp,
    'identity': identity,
  };

  /// Never throws: a value from another build or edited by hand falls back
  /// field by field, so the app can always connect.
  static WarpSettings fromJsonString(String? text) {
    if (text == null) {
      return defaults;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map<String, Object?>) {
      return defaults;
    }
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((T v) => v.name == name).firstOrNull ?? fallback;
    final Object? sni = decoded['masqueSni'];
    final Object? endpoint = decoded['endpoint'];
    final Object? identity = decoded['identity'];
    return WarpSettings(
      protocol: pick(
        WarpProtocol.values,
        decoded['protocol'],
        defaults.protocol,
      ),
      transport: pick(
        WarpTransport.values,
        decoded['transport'],
        defaults.transport,
      ),
      scan: pick(WarpScan.values, decoded['scan'], defaults.scan),
      obfuscation: pick(
        WarpObfuscation.values,
        decoded['obfuscation'],
        defaults.obfuscation,
      ),
      fingerprint: pick(
        WarpFingerprint.values,
        decoded['fingerprint'],
        defaults.fingerprint,
      ),
      masqueSni: sni is String && isValidMasqueSni(sni)
          ? sni
          : defaultMasqueSni,
      fragment: decoded['fragment'] == true,
      ech: decoded['ech'] == true,
      ipVersion: pick(
        WarpIpVersion.values,
        decoded['ipVersion'],
        defaults.ipVersion,
      ),
      endpoint: endpoint is String && isValidWarpEndpoint(endpoint)
          ? endpoint
          : null,
      quickReconnect: decoded['quickReconnect'] != false,
      throughWarp: decoded['throughWarp'] == true,
      identity: identity is int && identity >= 0 ? identity : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WarpSettings &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// A domain name Aether takes for `--masque-sni` (it refuses an address).
bool isValidMasqueSni(String value) {
  if (value.length > 253 || InternetAddress.tryParse(value) != null) {
    return false;
  }
  final RegExp label = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');
  final List<String> labels = value.toLowerCase().split('.');
  return labels.length >= 2 && labels.every(label.hasMatch);
}

/// `ip:port`, an IPv6 address in brackets: the port is required.
bool isValidWarpEndpoint(String value) {
  final RegExpMatch? match = RegExp(
    r'^(\[[0-9a-fA-F:.]+\]|[0-9.]+):([0-9]{1,5})$',
  ).firstMatch(value);
  if (match == null) {
    return false;
  }
  final String host = match.group(1)!.replaceAll(RegExp(r'[\[\]]'), '');
  final int port = int.parse(match.group(2)!);
  return InternetAddress.tryParse(host) != null && port >= 1 && port <= 65535;
}

/// Aether's command line for [settings], serving SOCKS5 on loopback [port],
/// keeping its WARP identities in its working directory.
List<String> aetherArguments(WarpSettings settings, int port) {
  final WarpProtocol protocol = settings.protocol;
  final String keys = 'warp-${settings.identity}';
  return <String>[
    '--bind',
    '127.0.0.1:$port',
    '--protocol',
    protocol.core,
    if (protocol == WarpProtocol.warpInWarp) '--gool-classic',
    '--scan',
    settings.scan.name,
    if (settings.obfuscation != WarpObfuscation.auto) ...<String>[
      '--noize',
      settings.obfuscation.name,
    ],
    '--ip',
    settings.ipVersion.core,
    if (settings.endpoint != null) ...<String>['--peer', settings.endpoint!],
    if (protocol.overMasque) ...<String>[
      '--masque-sni',
      settings.masqueSni,
      if (settings.transport == WarpTransport.http2) '--h2' else '--h3',
    ],
    if (settings.fragment) '--fragment',
    if (settings.ech) ...<String>['--ech', 'auto'],
    ...settings.fingerprint.arguments,
    if (settings.quickReconnect)
      '--quick-reconnect'
    else
      '--no-quick-reconnect',
    '--config',
    '$keys.toml',
    '--wg-config',
    '$keys.toml',
    '--masque-config',
    '$keys-masque.toml',
    '--log-level',
    'info',
  ];
}
