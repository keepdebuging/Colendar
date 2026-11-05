# Colendar

Colendar is a HarmonyOS time-planning app built with ArkTS and ArkUI. It currently supports task packages with timed steps, calendar scheduling in month/week/day views, moving and copying scheduled items, in-app start reminders, and guided execution sessions.

The repository does not currently grant a usage license. Until a `LICENSE` file is added by the maintainers, do not assume that reuse or redistribution is permitted. The current app supports versioned task-package import/export, Share Kit `knockShare` transmission, and explicitly enabled low-risk actions for opening apps, links, and authorized files. Dual-device sharing is still awaiting device verification. A public community workshop and high-privilege automation remain future work.

## Development environment

- DevEco Studio with HarmonyOS SDK `26.0.0` and compatible SDK `6.1.0(23)`.
- Node.js 22 for the configuration helper.
- OHPM and Hvigor from the matching DevEco Studio toolchain.
- Windows for the provided PowerShell scripts and the configured self-hosted verification runner.

Use DevEco Studio's integrated terminal or set `HARMONY_HVIGOR` to the Hvigor entry point installed with the local toolchain. The repository does not include a Hvigor wrapper.

## Configure and build

1. Install dependencies with `ohpm install` from the repository root.
2. Run `node scripts/configure-build.mjs` to create a local `build-profile.json5`.
3. Open the project in DevEco Studio and build the `entry` module, or run `scripts/build-check.ps1` from PowerShell.
4. For local signing, copy `config/signing.local.example.json` to the ignored `config/signing.local.json`, replace every example value with your own signing material, then rerun the configuration helper. Never commit certificates, profiles, keystores, or passwords.

Without a local signing file, the generated profile remains unsigned and is suitable for development builds where the installed toolchain permits them.

## Tests and verification

Run `scripts/test-check.ps1` to invoke the registered HarmonyOS test task. The automated workflow expects a self-hosted Windows runner labelled `harmonyos-sdk` with the required SDK, OHPM, and Hvigor toolchain installed. HAP build success, business test results, and device validation are separate results; this workflow does not perform device testing.

## Data and recovery

Task packages, scheduled events, and execution sessions are stored together in a versioned snapshot. A previous validated snapshot is retained for recovery. Startup validates the current snapshot before opening the main screen; unreadable data opens a recovery page with retry, backup-copy, previous-snapshot restore, and explicit reset actions.

## Contributing

Keep schedule validation in the data layer as well as the UI, preserve customized scheduled copies when templates change, and make persistence failures visible to the caller. Use the build and test entry points above when the HarmonyOS toolchain is available. Do not add signing material or user task contents to diagnostic reports.
