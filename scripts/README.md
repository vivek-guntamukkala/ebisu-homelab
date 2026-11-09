Bootstrap and deploy helpers.

- `fetch-ip-schema.sh` (Linux, macOS, WSL, Git Bash) and `fetch-ip-schema.ps1` (Windows PowerShell): write the git-ignored `schema/ip-schema.yaml` from the Bitwarden secret `IP_SCHEMA_B64` using `bws run`. See `docs/secrets.md`.
