<!-- SPDX-License-Identifier: MIT -->

# Secrets scan

Two layers keep secrets and real addressing out of this public repository.

1. **Local pre-commit hook** (`.githooks/pre-commit`): scans the staged changes and
   blocks the commit on a finding. It fails closed: if `gitleaks` is missing, the
   commit is refused.
2. **CI check** (`.github/workflows/secrets-scan.yml`): scans the full history on every
   push and pull request, using a pinned, checksum-verified gitleaks binary.

Both read `.gitleaks.toml`: the default ruleset plus a rule that rejects private
(RFC 1918) IPv4 addresses. Documentation-range addresses (RFC 5737, as used in
`schema/ip-schema.example.yaml`) are allowed.

## One-time setup on Windows ARM64 (`odysseus`)

1. Download `gitleaks_8.30.1_windows_arm64.zip` and `gitleaks_8.30.1_checksums.txt`
   from the [gitleaks releases page](https://github.com/gitleaks/gitleaks/releases).
2. Compare the zip's hash with the checksums file (PowerShell):
   ```powershell
   (Get-FileHash .\gitleaks_8.30.1_windows_arm64.zip -Algorithm SHA256).Hash
   Select-String windows_arm64 .\gitleaks_8.30.1_checksums.txt
   ```
   The two hashes must match (ignore letter case).
3. Extract `gitleaks.exe` to a folder on your `PATH` (for example `%USERPROFILE%\bin`),
   then check it with `gitleaks version`.
4. In the repo, enable the hook and mark it executable:
   ```powershell
   git config core.hooksPath .githooks
   git update-index --chmod=+x .githooks/pre-commit
   ```

## Notes

- To test the hook, stage a throwaway file containing a private address (an RFC 1918
  address, for example one starting with 192 dot 168), written out in full; the commit
  must be refused. Unstage and delete the file afterwards.
- Gitleaks is described by its maintainer as feature complete and receiving security
  patches only, with the maintainer's attention moving to a successor project
  (Betterleaks). Revisit the choice if releases stop.
- `--no-verify` skips the local hook but not the CI check.
