# StupidMetrics

The Swift client for stupid metrics (`metrics.stupidtech.net`): anonymous usage analytics and error reporting for Stupid Tech apps. iOS 17+ and macOS 14+, no dependencies, safe to link into app extensions.

It is anonymous by design: it sends a random install id, app version, build, environment, platform, OS version and device model, plus the event names and low-cardinality properties the app chooses. MetricKit crashes, hangs and diagnostics are forwarded on devices.

## Install

```swift
.package(url: "https://github.com/stephancill/stupid-metrics-swift", from: "0.2.1")
// target dependency: .product(name: "StupidMetrics", package: "stupid-metrics-swift")
```

`stupid-app` builds apps with package dependencies from 0.0.27.

## Use

An app needs an ingest key, which the service's admin registers (`POST /admin/apps`). Configure it at launch and record events:

```swift
import StupidMetrics

StupidMetrics.configure(appKey: "smk_…")

StupidMetrics.track("refresh", properties: ["network": "x", "trigger": "manual"], value: durationMs)
StupidMetrics.error("source_error", error: error, properties: ["network": "x"])
StupidMetrics.isEnabled = false // user opt-out: drops the queue and the install id
```

Names and property keys use lowercase letters, digits and `_ . : -`. Property values are short strings (64 characters), at most 8 per event. `error(_:error:)` sends only the error's type and case (`URLError.-1009`, `DecodingError.keyNotFound`), never its localized text. Never send names, handles, user content, URLs, ids or tokens as properties.

The package sends `session_start` automatically. A new session starts when the app returns after 30 minutes in the background. Batches go out every 5 minutes and when the app is backgrounded, and are kept on disk while offline. `docs/IMPLEMENTATION.md` has the details.

## Develop

```sh
swift test
swiftformat Sources/ Tests/ Package.swift
```

## License

Apache 2.0 (`LICENSE`).
