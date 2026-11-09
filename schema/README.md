# schema

`ip-schema.example.yaml` shows the structure of the real address plan, filled with
dummy values from the documentation range (RFC 5737). The real `ip-schema.yaml` is a
Bitwarden Secrets Manager secret (project `iac-deploy`), pulled at deploy time by
`scripts/load-secrets.sh`, and is git-ignored. It must never be committed.
