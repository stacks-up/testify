# Testify

A single-file Swift tool that captures macOS security settings as screenshots
and compiles them into a dated BYOD device controls attestation PDF on your
Desktop.

## What it captures

1. **Software Update** — current update status
2. **Lock Screen** — auto-lock timeout settings
3. **Privacy & Security** — "Allow applications from" and FileVault status
4. **System Integrity Protection** — `csrutil status`
5. **Gatekeeper** — `spctl --status`
6. **XProtect** — XProtect processes in Activity Monitor
7. **Password Policy** — the "BYOD Password Policy" profile detail in System Settings > General > Device Management, showing the description, install date, and enforced payload values (minimum length, lockout, no expiry) — authoritative, OS-rendered evidence
8. **1Password** — Finder "Get Info" window proving the app is installed and its version (skipped if not installed). The app is never launched, so no vault contents are exposed.

## Build

The tool ships as a signed `Testify.app` bundle so that macOS attributes
its permissions to **the app itself, not the terminal that launched it**.

```bash
# One time per machine — create the self-signed signing identity:
./create-signing-cert.sh

# Each build — compile, bundle, and sign:
./package.sh
```

All build output lands in `dist/` (the source tree stays clean):

```
dist/
├── Testify.app                         # signed, permission-owning app
└── BYOD-PasswordPolicy.mobileconfig    # password-policy profile
```

## Run

Launch through LaunchServices (double-click in Finder, or):

```bash
open dist/Testify.app
```

> Do **not** run the inner binary directly
> (`dist/Testify.app/Contents/MacOS/Testify`).
> A binary launched as a child of Terminal inherits Terminal as its TCC
> "responsible process", which is exactly why permissions used to land on
> Terminal. `open` launches the app as its own responsible process.

A small progress window (status line, progress bar, and a scrolling log) appears
while it runs — since there's no terminal output when launched as an `.app`. It
parks in the top-left, clear of the windows being captured. When finished it
shows "Done"; close the window to quit.

Output: `~/Desktop/<date> BYOD Device Controls Attestation.pdf` (opens automatically when done).

## Required permissions

Grant these to **Testify.app** (no longer to Terminal):

| Permission | Location | Why |
|---|---|---|
| **Accessibility** | System Settings > Privacy & Security > Accessibility | Read and interact with UI elements (scroll, click, set search fields) |
| **Screen Recording** | System Settings > Privacy & Security > Screen Recording | Capture window screenshots |
| **Automation** | System Settings > Privacy & Security > Automation | Drive Terminal / System Settings / Activity Monitor via Apple Events |

On first launch the app prompts for Accessibility, then checks Screen Recording
(and prompts for Automation as it drives each app). Grant each one and reopen
the app — macOS only applies a fresh grant to the next launch.

**Screen Recording is the awkward one.** Captures are taken by a `screencapture`
child process, which never raises a prompt of its own and simply writes nothing
when denied, so the app asks on its own behalf via
`CGRequestScreenCaptureAccess`. Two things to know:

- It is **never granted inline.** Unlike Camera or Microphone, there is no
  Allow button — the system prompt only offers to open System Settings. You
  always finish the grant with a toggle under **System Settings > Privacy &
  Security > Screen Recording**. The app opens that pane for you.
- The prompt appears **at most once per app identity.** Once TCC has recorded
  any decision, the request returns false silently and nothing appears again.

If `Testify` isn't listed in that pane at all, clear the recorded decision and
relaunch:

```bash
tccutil reset ScreenCapture biz.stack.testify
open dist/Testify.app
```

**Permissions persist across rebuilds.** The app is signed with a stable
self-signed identity, so its designated requirement
(`identifier "biz.stack.testify" and certificate leaf = …`) does not
change when you recompile — grant once. (This was not true of the old bare
binary, whose ad-hoc signature changed every build.)

## Password policy (configuration profile)

The password policy is enforced by a managed configuration profile rather than a
local `pwpolicy` command, so it shows up as an auditable control under **System
Settings > General > Device Management**. Page 7 of the attestation captures the
profile's detail sheet — description, install date, and enforced payload values
— directly from that pane.

```bash
# Generate the profile (mirrors the existing device policy:
# 10-char minimum, no expiry, no complexity, lock after 5 fails):
./make-password-profile.sh
```

This writes `dist/BYOD-PasswordPolicy.mobileconfig`. Install it **before** running
the attestation so page 7 can capture it:

1. Double-click `dist/BYOD-PasswordPolicy.mobileconfig`.
2. Approve it in **System Settings > General > Device Management** (admin required).

Verify / remove:

```bash
profiles list                     # user-scope profiles
sudo profiles list                # includes this System-scope profile
sudo profiles remove -identifier biz.stack.byod.passwordpolicy.profile
```

> **Fidelity note.** A passcode-policy payload matches the password-strength rules
> exactly (length, no expiry, no complexity) but cannot express
> `minutesUntilFailedLoginReset=15`, and treats `maxFailedAttempts` as a login
> delay rather than an account lock. For a byte-exact reproduction of those
> lockout settings, use `pwpolicy -setglobalpolicy` instead — but that produces
> no managed profile, so page 7 would have nothing to capture and you'd evidence
> it manually (e.g. `pwpolicy -n /Local/Default -getglobalpolicy` in a terminal).
