# Contributing

Thanks for helping. Bug reports, fixes and support for more agents are all welcome.

## Reporting a bug

Open an issue with:

- your macOS version and which agents you use;
- what you expected and what happened;
- if values look wrong, the relevant lines from
  `log stream --predicate 'subsystem == "<your bundle prefix>.agentsusagewatch"'`.

Please don't paste tokens, `auth.json` or full session logs. The app never needs them, and neither does a bug report.

## Making a change

1. Build with `./install.sh` (see the README for setup).
2. Keep changes small and focused; one fix or feature per pull request.
3. If you touch parsing, alert rules or the helper scripts, add or update a check in `Checks/ModelCheck/main.swift`
   and run the checks (the command is in the README). CI runs them too.
4. Describe what you changed and how you tested it in the pull request.

## Adding an agent

Write a reader in `App/Accounts.swift` that finds the agent's local data and returns its windows (5-hour and weekly
percentages and reset times), like `Codex` does, and register it in `Providers.discover` and `Providers.read`. Read only
local files the agent already writes; don't add network calls, and never use, log or store credentials. Add a fixture-based check for the
parser, with any ids or personal data stripped.

By contributing you agree that your contribution is licensed under the MIT License.
