# Security

## Supported versions

Only the latest release gets fixes.

## Reporting a vulnerability

Report it privately through [GitHub Security Advisories](https://github.com/oddurs/common-command/security/advisories/new), not in a public issue.

You'll get an acknowledgement within a week. If the report is confirmed, a fix ships in a new release and the advisory is published with credit, unless you'd rather stay anonymous.

<!-- standard:begin surface -->
Common Command runs unprivileged and asks for no permissions. It makes no network connections of its own; web searches and links open in your browser. It reads the folders apps live in, the System Settings extension bundles, and file names from the Spotlight index of your home folder. It keeps a history of what you opened, and the queries you opened it with, in `~/Library/Application Support/Common Command/usage.json`. Reports about how queries reach Spotlight or how the calculator parses input are especially welcome.
<!-- standard:end surface -->
