# ADR 0001: Native SwiftUI app, pure-Swift core, SQLite via GRDB, no network

Date: 2026-11-05 · Status: accepted (code location decided by Saša on 2026-11-05)

## Decision

- One Xcode project with three modules: `InvoicingCore` (pure Swift, no dependencies), `InvoicingData` (SQLite through GRDB.swift 7), `FA` (SwiftUI macOS app).
- Oldest supported macOS: 14 Sonoma (to be confirmed against the user's Mac).
- Swift 6 language mode with complete strict concurrency.
- App Sandbox on; the network-client entitlement is deliberately absent.
- Money uses `Decimal`; amounts are stored as integers in minor units with a currency code; exchange rates as decimal text with three decimals, as published by the ČNB.
- Issued documents are stored as frozen snapshots and never edited; every state change is appended to an audit log.
- PDFs are drawn with Core Graphics; QR codes with Core Image.

## Alternatives rejected

- SwiftData: weaker control over migrations and immutability for v0.1; harder to inspect and export.
- Core Data: heavier, same inspectability problem.
- Downloading rates inside the app: would need the network entitlement; v0.1 imports the ČNB yearly text file instead (decision 3 of the proposal, pending).

## Consequences

- GRDB is the only third-party dependency.
- The core compiles on Linux, so CI tests it on a cheap Linux runner; the full package and the app build on a hosted Mac.
- The bundle identifier `com.github.alexpaur66-ai.fa-mac` names the sandbox container; change it before the first real data is entered, not after.
