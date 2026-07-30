# Security

## Reporting

Report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/reghis86/context-forge/security/advisories/new).
Please do not open a public issue for anything exploitable. Expect a first response within a week.

## Threat model

ContextForge is a plugin that installs **shell hooks which run automatically** on Claude Code
lifecycle events (session start/end, before and after tool calls). It has no server component and
makes no network calls of its own, but the hooks execute with your user's privileges on every
session in a repository where the plugin is active.

Consequences worth knowing before you install it:

- **Hooks run untrusted-adjacent input.** They receive tool payloads as JSON on stdin. They parse
  with `jq` and never `eval` it, but a parsing bug is a local code-execution surface.
- **State is written outside the repository** — `~/worklogs/` (decisions, run logs, session
  diaries) and `<IDE_DIR>/lessons/` (failure ledgers). Those files can contain fragments of command
  output and error text from your work. They are deliberately kept out of any git repository, but
  they are plaintext on disk. Review them before sharing.
- **`safe-exec` and `log-analyzer` spill large command output to `~/worklogs/logs/`.** If a command
  prints a secret, that secret lands in a log file.
- **Manifest generation reads your source tree.** It records symbol names and paths only — never
  file contents — into `<IDE_DIR>/shadow/`.

## Not vulnerabilities

- A hook blocking a tool call (`grep`, an unreviewed `git commit`, a sub-agent spawn). That is the
  product working; see `SKIP_REVIEW` in [CONTRIBUTING.md](CONTRIBUTING.md).
- Advisories in `devDependencies` that are unreachable at runtime — the plugin ships shell scripts
  and Markdown, and nothing under `node_modules/` is executed by the hooks.
