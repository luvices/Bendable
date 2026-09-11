# Security policy

## Reporting a vulnerability

Please report security issues privately rather than in a public issue.

Use GitHub's [private vulnerability
reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository: **Security → Report a vulnerability**. If that is
unavailable to you, open a public issue containing only the words "security
report" and a way to reach you, and a maintainer will arrange a private channel.

## What runs with elevated privileges

One thing, on request, and never in the background.

The lid-shut wakefulness switch runs `/usr/bin/pmset -a disablesleep 0|1` through the
standard macOS authorization dialog. The command is a literal in
`Bendable/Power/SleepGuard.swift` with a single digit interpolated that the same file
produces; no preference, user input or remote value reaches a shell. Bendable installs
no helper tool and no daemon, holds no authorization between one use and the next, and
never sees or stores the password. With that switch untouched, Bendable runs entirely
as an ordinary unprivileged user process.

Please include:

- the macOS version and Mac model;
- what an attacker gains, and what access they need to start;
- steps to reproduce, or a proof of concept;
- the commit or release the report applies to.

You can expect an acknowledgement within 7 days and an assessment within 30.
Fixes are released as a patch version and credited in the release notes unless
you would rather not be.

Please do not run tests against machines you do not own.

## Supported versions

Only the latest release is supported. Fixes are not backported.

## Threat model

Bendable is an unsandboxed menu bar app that runs as the logged-in user. It has
no network access, no privileged helper, no daemon, no kernel extension, and no
setuid component. It does not require SIP to be disabled and does not ask anyone
to weaken macOS security settings.

What it touches:

- **A built-in HID sensor**, opened read-only through `IOHIDManager`. No
  entitlement is involved. It writes nothing to the device.
- **`IOPMrootDomain`**, read-only, for clamshell state.
- **Screen Recording (TCC)**, optional, requested only on explicit user action
  and used for single still images. See [PRIVACY.md](PRIVACY.md).
- **`SMAppService`**, only when the user turns on Launch at login.
- **Its own `UserDefaults` domain.** It writes no other file.

Reports of particular interest:

- any path by which a captured desktop still could reach disk, another process,
  or a locked session;
- anything that lets Bendable block or delay sleep, wake or shutdown;
- an overlay window state that could obscure the screen without the lid moving;
- privilege or permission escalation beyond the list above.

## Verifying a download

Every release ships a `.sha256` file next to the DMG:

```bash
shasum -a 256 -c Bendable.dmg.sha256
```

Releases built with the maintainer's signing secrets are signed and notarized;
verify with `codesign --verify --deep --strict --verbose=2` and `spctl -a -vv`.
CI artifacts from ordinary commits are ad-hoc signed and will not pass `spctl`;
that is expected.
