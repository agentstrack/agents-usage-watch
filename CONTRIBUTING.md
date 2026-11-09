# Contributing

Thanks for helping. Bug reports, fixes and support for more agents are all welcome.

## Reporting a bug

Open an issue with:

- your macOS version, the app version (Settings › About) and which agents you use;
- what you expected and what happened;
- if values look wrong, the relevant lines from
  `log stream --predicate 'subsystem == "<your bundle id>"'`. The bundle id is your `BUNDLE_ID_PREFIX` plus
  `.agentsusagewatch`; for an installed copy, `defaults read "/Applications/Agents Usage Watch.app/Contents/Info" CFBundleIdentifier`.

Please don't paste tokens, `auth.json` or full session logs. The app never needs them, and neither does a bug
report. Check [docs/troubleshooting.md](docs/troubleshooting.md) first; many problems are covered there.

## Building

You need Xcode 15 or later and XcodeGen. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, set your
team ID and a bundle ID prefix, then run `./install.sh`. Full steps are in [docs/installation.md](docs/installation.md);
how the pieces fit together is in [docs/architecture.md](docs/architecture.md).

## Making a change

1. Keep changes small and focused; one fix or feature per pull request.
2. If you touch parsing, alert rules or the helper scripts, add or update a check in
   `Checks/ModelCheck/main.swift`, and run the checks. They need no Xcode:

   ```sh
   swiftc -o /tmp/chk Shared/Model.swift App/Parse.swift App/Alerts.swift App/Accounts.swift \
     App/StatusLine.swift Checks/ModelCheck/main.swift && /tmp/chk
   ```

   CI runs the same command on every push and pull request.
3. If the change is visible, build with `./install.sh` and try it.
4. If it changes behavior described in `README.md` or `docs/`, update those too.
5. Describe what you changed and how you tested it in the pull request.

## Adding an agent

Write a reader in `App/Accounts.swift` that finds the agent's local data and returns its windows (5-hour and weekly
percentages and reset times), like `Codex` does, and register it in `Providers.discover` and `Providers.read`. Read
only local files the agent already writes; don't add network calls, and never use, log or store credentials. Add a
fixture-based check for the parser, with any ids or personal data stripped. The steps, and what to do for an agent
with a status line, are in [docs/architecture.md](docs/architecture.md#adding-an-agent).

By contributing you agree that your contribution is licensed under the MIT License.
