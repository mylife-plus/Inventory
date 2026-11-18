/// Device sync relay (Cloudflare Worker + D1). Public URL only — the relay
/// stores AES-GCM ciphertext and can never read shop data.
const String kSyncServerUrl = String.fromEnvironment(
  'SYNC_URL',
  // Testing only: --dart-define=SYNC_URL=http://10.0.2.2:8787 (local worker).
  defaultValue: 'https://inventory-sync.gjng57w88w.workers.dev',
);

/// Poll interval while the app is open and at least one device is paired.
const Duration kSyncPollInterval = Duration(seconds: 5);

/// Full local change scan fallback (writes normally trigger a scan at once).
const Duration kSyncScanInterval = Duration(seconds: 30);
