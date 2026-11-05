# Building and running FA on a Mac

Requirements: a Mac on macOS 14 or newer (the app targets 14.0 and runs on the current macOS; CI builds it with Xcode 16.4, a newer Xcode is fine) and a few tens of GB of free disk for Xcode.

## Once

1. Install **Xcode** from the App Store (free, large). When it first asks which platforms to install, choose **macOS only**: the iOS simulators are several GB each and are not needed; they can be added later under Xcode → Settings → Components. Open Xcode once and let it install its components.
2. **Xcode → Settings → Accounts**: add your Apple ID. It is used only to sign the app for your own Mac; no paid developer membership is needed.
3. Get the code: **Xcode → File → Clone…** with `https://github.com/alexpaur66-ai/FA-mac.git`, or in Terminal `git clone https://github.com/alexpaur66-ai/FA-mac.git`.
4. In Terminal, inside the repository: `scripts/doctor.sh`. Fix anything it marks FAIL.
5. Open `App/FA.xcodeproj`, pick the **FA** scheme, press **Run**. The first build resolves the GRDB package from GitHub, which needs an internet connection once; the app itself never uses the network.

## Each update

**Source Control → Pull** (or `git pull`), then **Run**.

## Where the data lives

`~/Library/Containers/com.github.alexpaur66-ai.fa-mac/Data/Library/Application Support/FA/fa.sqlite` — one SQLite file (exported PDFs go to the folder you choose). Keep this live file out of iCloud Drive and every other synced folder: SQLite in a synced folder gets corrupted. Back it up with the app's backup command (coming) or Time Machine; a backup copy may live in your cloud folder. Turn on FileVault.

For tests and previews the location can be overridden with the environment variables `FA_DATABASE_PATH` (a file path) or `FA_IN_MEMORY_DATABASE=1`.

## If something fails

Copy the red error text from Xcode (or the output of `scripts/doctor.sh`) into the project thread. CI builds every commit on a hosted Mac first, so a local failure is usually a setup problem, not a code problem.
