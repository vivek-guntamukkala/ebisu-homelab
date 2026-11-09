# Secrets handling

Secrets live in Bitwarden Secrets Manager (free organisation, three projects) and
are injected into a process at run time with `bws run`. Nothing is written to the
repo, and no `.env` files are used.

## Layout

- Organisation `Ebisu-Homelab` with three projects: `apps`, `iac-deploy`, `mcp-layer`.
- One machine account per project, read-only on its own project.
- Run commands with the token of the project that command needs.

## Providing the token

The token is kept in the shell session only. Never paste it into chat or a file.

PowerShell:

    $sec = Read-Host -AsSecureString 'BWS token'
    $env:BWS_ACCESS_TOKEN = [System.Net.NetworkCredential]::new('', $sec).Password

Bash:

    read -rs BWS_ACCESS_TOKEN && export BWS_ACCESS_TOKEN

## Naming

UPPER_SNAKE_CASE. OpenTofu variables use the `TF_VAR_` prefix. The IP schema is
`IP_SCHEMA_B64`.

## Using secrets

    bws run -- tofu apply

`bws run` exports every secret of the token's project into that one process. Do not
print the environment.

## IP schema

The real schema is stored base64-encoded as `IP_SCHEMA_B64` in `iac-deploy`.

Encode locally (never through chat):

    # PowerShell
    [Convert]::ToBase64String([IO.File]::ReadAllBytes('schema/ip-schema.yaml'))
    # bash
    base64 -w0 schema/ip-schema.yaml

Fetch it onto a machine with `scripts/fetch-ip-schema.sh` or
`scripts/fetch-ip-schema.ps1`. The output `schema/ip-schema.yaml` is git-ignored.

On Windows, local scripts may be blocked by the execution policy. Run the script with a
process-only bypass, which changes no system setting:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\fetch-ip-schema.ps1

## Open

Token delivery to Linux guests (O19) is undecided.
