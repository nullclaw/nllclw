# Security Policy

## Supported Versions

Security fixes are handled for the current `main` branch and the latest tagged
release.

| Version | Supported |
|---|---|
| `main` | Yes |
| Latest release | Yes |
| Older releases | Best effort |

## Reporting A Vulnerability

Do not open a public issue for a vulnerability, credential leak, private log, or
exploit path.

Report security issues privately through GitHub Security Advisories for
`nullclaw/nllclw`. If you cannot access advisories, contact a maintainer
privately through GitHub before publishing details.

Include:

- affected version or commit;
- operating system and build options;
- reproduction steps;
- expected and actual behavior;
- impact and whether credentials, local files, shell execution, Telegram,
  WebSocket, memory, or provider configuration are involved.

Maintainers will acknowledge valid reports as soon as practical, investigate the
scope, and coordinate a fix or mitigation before public disclosure.

## Security Boundaries

`nllclw` is a local AI assistant. The default build has no shell tool and uses
Zig stdlib adapters only. The optional `shell_exec` tool is available only in
builds made with `-Dshell-tool=true`.

When reporting or reviewing security-sensitive changes, pay special attention to:

- provider keys and request headers;
- local filesystem access and path validation;
- memory and state files;
- Telegram and WebSocket authentication;
- compatible-provider HTTP URL validation;
- scheduler and macro tool configuration;
- shell execution in `-Dshell-tool=true` builds.
