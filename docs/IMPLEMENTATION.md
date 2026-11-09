# Implementation Notes

How the client works today, by topic. The service it sends to (stupid metrics, `metrics.stupidtech.net`) is a separate, private repository.

## Client

- `StupidMetrics` is a static facade over an `Engine` actor. Calls before `configure` are dropped with a fault log.
- The queue is `Application Support/StupidMetrics/queue.json`, excluded from backup. It holds batches by context, so events queued before an update are sent with the version that recorded them. It's saved on backgrounding, after each flush, and right away for errors (they often precede a crash). The queue keeps at most 2,000 events; events older than 7 days are dropped.
- Send results: 2xx removes the events; 429, 5xx and network errors keep them for the next flush; any other status drops them (resending a rejected batch would fail forever).
- Environment: `simulator` at compile time; `development` when the bundle has `embedded.mobileprovision` (TestFlight and App Store installs don't); otherwise the App Store receipt's file name, `sandboxReceipt` on TestFlight. StoreKit's `AppTransaction` was used first, but it needs the network and reported `unknown` on a TestFlight install (observed 2026-10-29). `appStoreReceiptURL` is deprecated, so it's read through KVC to keep the warning out of apps. Resolved on the first flush; queued batches are stamped then.
- Backgrounding uses `ProcessInfo.performExpiringActivity` rather than `UIApplication.beginBackgroundTask`, which keeps the package safe to link into app extensions.
- MetricKit payloads are written to `diagnostics/` first and deleted after a successful upload. The subscriber is retained statically because `MXMetricManager` holds subscribers weakly. MetricKit delivers only on devices, at most daily.
- `describe(_:)` uses `Mirror` to get an enum case label without its associated values. For payload-less cases it uses the case name unless the type is `CustomStringConvertible` (checked on the metatype, since every value bridges to `NSError`, which is), in which case it falls back to the `NSError` code.
- Opting out deletes the queue, saved diagnostics and the install id.

## Releases

- Moved out of the private stupid-metrics repository at `v0.2.1` so public apps can depend on it by URL; the sources are unchanged from that release.
