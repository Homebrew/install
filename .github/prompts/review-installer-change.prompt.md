--

description: "Review Homebrew installer changes for portability, safety, and regressions"
name: "Review Installer Change"
argument-hint: "Select the installer change to review"
agent: "cryptomua"
tools: [read, search, execute]
---
Review the requested Homebrew installer change in the current workspace.

Inspect the relevant code and nearby documentation before forming conclusions. Prioritize:
- Shell correctness and failure handling under `set -e` and pipelines
- Portability across supported macOS and Linux environments
- Quoting, input validation, privilege boundaries, cleanup, and idempotency
- Regressions in install, upgrade, and uninstall behavior
- Missing focused tests or cheap validation commands

Report findings first, ordered by severity. For each finding, include the affected file and line, the concrete failure scenario, and a concise fix direction. Do not report style-only concerns. If there are no findings, say so clearly and list only meaningful residual risks or test gaps. Keep the review focused on the requested change and do not edit files unless explicitly asked.

Review the selected installer change and its surrounding workspace context:
${selection}
