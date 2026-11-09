# AGENTS.md

Rules for AI agents working in this repository.

## Stack

- Swift package, Swift 6 language mode, iOS 17+ / macOS 14+, no dependencies. One library product, `StupidMetrics`.
- The service it sends to is stupid metrics (`../stupid-metrics`, private): a Cloudflare Worker whose request shapes and limits are in its `src/schemas.ts`.

## Before making changes

- Read `README.md` and `docs/IMPLEMENTATION.md`.
- Keep the client's limits (`Sources/StupidMetrics/Models.swift`) in sync with the service's `src/schemas.ts`; change both together.
- The client is anonymous by design: never add fields that identify a person (names, handles, content, URLs, ids beyond the random install id, IP-derived data).
- Keep it safe to link into app extensions (no `UIApplication.shared`).

## Committing

- Run `swiftformat Sources/ Tests/ Package.swift` and `swift test` before committing.
- Update `docs/IMPLEMENTATION.md` when a change makes something there untrue or adds a decision worth knowing. It describes the current state by topic, not a changelog, and is public: never include secrets or personal information.
- Use Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`).

## Releasing

- Apps pin releases: after changing the package, tag `vX.Y.Z` (`git tag -a vX.Y.Z -m "StupidMetrics X.Y.Z"`), push the tag, create the GitHub release (`gh release create vX.Y.Z --notes "…"`), then bump the apps that use it (stupid social, stupid wallet: `swift package update stupid-metrics-swift`, commit `Package.resolved`).
