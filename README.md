# FA-mac

Offline, privacy-first invoicing and light CRM for a Czech s.r.o., written in Swift for macOS.
Česky: fakturační aplikace pro Mac, která běží úplně offline (faktury, zálohy, daňové doklady k přijaté platbě, klienti, platby).

Status: **scaffold** (nothing usable yet). The design is in the proposal document
"Offline Mac invoicing app — architecture & MVP proposal" (private Claude Doc; link in the project thread).

## What is where

| Path | Purpose |
| --- | --- |
| `Package.swift`, `Sources/InvoicingCore` | Pure Swift core: money, VAT rules, exchange rates, document rules, numbering, payment QR strings. No UI, no database. Unit-tested, also builds on Linux. |
| `Sources/InvoicingData` | SQLite persistence through [GRDB.swift](https://github.com/groue/GRDB.swift): schema, migrations, repositories. |
| `App/FA.xcodeproj`, `App/FA` | The macOS app (SwiftUI). App Sandbox on, **no network entitlement**. |
| `Tests/` | Swift Testing suites for the core and the data layer. |
| `docs/` | Architecture decisions, the Czech VAT compliance checklist, Mac setup notes. |
| `scripts/doctor.sh` | Checks a Mac for everything needed to build and run. |
| `.github/workflows/ci.yml` | Builds and tests on every push: core on Linux, everything on a hosted Mac. |

## Build it on your Mac (once)

1. Install Xcode from the App Store and open it once so it installs its components.
2. In Xcode, **Settings → Accounts**, sign in with your Apple ID (free; used only to sign the app for your own Mac).
3. Clone this repository: in Xcode, **File → Clone…** (or `git clone https://github.com/alexpaur66-ai/FA-mac.git`).
4. Run `scripts/doctor.sh` in Terminal from the repository folder; it tells you if anything is missing.
5. Open `App/FA.xcodeproj`, select the **FA** scheme and press **Run**.

Every later update is `git pull` (or **Source Control → Pull** in Xcode) and **Run** again.

## Principles

- Offline only. The app cannot open network connections; the sandbox has no network permission.
- One SQLite file in your user Library; FileVault protects it at rest.
- Issued documents are immutable; every state change is logged.
- Decimal arithmetic everywhere; never floating point for money.
- Every Czech VAT rule in the core cites its paragraph of zákon č. 235/2004 Sb.
