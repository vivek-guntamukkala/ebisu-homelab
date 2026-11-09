<!-- SPDX-License-Identifier: MIT -->

# Homelab implementation plan

A reproducible homelab on a single Proxmox node, fronted by OPNsense and
Cloudflare, with secrets and agentic (MCP) access defined as code. Identity and
monitoring are designed but **on hold**; the core platform comes first.

This is the build plan: **intent first, then steps**. Environment-specific values
(addresses, credentials, raw device configs) are deliberately absent. They live
outside this repository (see Sections 2.3 and 2.7).

> Status legend: `[ ]` not started · `[~]` in progress · `[x]` done · **on hold** =
> designed, not scheduled.
> Phases are ordered so nothing depends on something built later. Phase numbers are
> stable identifiers, not the execution order; the table below gives the order.

**Diagrams:** [`docs/data-flow.svg`](docs/data-flow.svg) and
[`docs/topology.svg`](docs/topology.svg) show the target state, with no addresses.

| Order | Phase | Summary |
| --- | --- | --- |
| 1 | Phase 0 | Repository, workstation and secrets |
| 2 | Phase 1 | Proxmox as code and host hygiene |
| 3 | Phase 2 | OPNsense MCP (read and guarded write) |
| 4 | Phase 3 | Network segmentation, through the MCP |
| 5 | Phase 4 | Split DNS and tunnel |
| 6 | Phase 5 | Proxmox MCP (read-only) and performance gate |
| 7 | G1 | Jellyfin media server |
| 8 | Phase 9 | Remaining write tools |
| 9 | Phase 7 | Retire `fafnir` (last step) |
| on hold | Phase 6, Phase 8 | Identity; SIEM and SOAR |

---

## 0. Design principles

When a choice is ambiguous, resolve it in favour of these.

1. **Zero inbound.** Both WAN links sit behind CGNAT and no port is ever
   forwarded. All ingress arrives through an outbound Cloudflare Tunnel. This is a
   security property first and a CGNAT workaround second.
2. **Least privilege.** Every token, account and MCP tool gets the narrowest
   capability that does the job. Read-only until write is proven necessary.
3. **Reproducible from the repo.** Infrastructure, service config and docs live in
   git. A rebuild is `tofu apply` plus documented manual steps.
4. **Secrets never touch git.** Secrets live in Bitwarden Secrets Manager and are
   injected at deploy time. The repo holds only `*.example` templates and
   sanitized exports.
5. **Break-glass is real.** Every remotely gated system keeps a local account, and
   a physical last-resort path depends on nothing else working.
6. **Narrow gateways, not raw passthrough.** MCP servers expose specific, audited
   tools, never a raw API proxy.
7. **Phase for safety, not speed.** Write capability is introduced narrowly, only
   where a phase needs it, always with timed auto-revert. Broader write waits until
   the pipeline is measured and trusted.
8. **Observe before automating.** Monitoring and automation are on hold. They are
   added only after the core platform exists and its performance has been measured
   (Phase 5 gate).
9. **Changes only through code.** OPNsense configuration changes go through the MCP
   server or OpenTofu. The web UI is for inspection only, apart from three documented
   exceptions: API bootstrap and key creation, firmware upgrades, and console or
   direct-cable recovery.
10. **Core platform first.** Authentication and security tooling are deliberately
    deferred and added gradually. Until then every system uses local accounts, the MCP
    servers stay LAN-only, and the one public service (Jellyfin) carries a documented,
    temporary exposure.

---

## 1. Environment

### 1.1 Host (`olympus`)

| Property | Value |
| --- | --- |
| Hardware | Dell OptiPlex 7050 (i7-6700, 4C/8T), ~180 W PSU |
| RAM | 31 GiB (the binding constraint) |
| Boot disk | 1 TB SATA SSD, ZFS |
| VM disk | 1 TB NVMe, LVM |
| NICs | 1 integrated Gigabit + 1 dual-port Intel Gigabit |
| Hypervisor | Proxmox VE 8.4, single node, no-subscription repository |

> Write-heavy logging stays off the boot SSD (DRAM-less QLC). SIEM indices and
> other hot write paths go on the NVMe.

### 1.2 Guests

| ID | Name | Role | Notes |
| --- | --- | --- | --- |
| 100 | hermes | OPNsense firewall | 3 virtio NICs on vmbr0/1/2 |
| 101 | fafnir | Workstation VM | Stopped. Removed last, after the active plan (Phase 7) |
| 104 | jormungandr | Unused | Removed in Phase 1 |
| TBD | jellyfin | Media server | Planned, DMZ (milestone G1) |

### 1.3 Admin workstation (`odysseus`)

All administration, including the Claude Code client that talks to the MCP
servers, happens from one dedicated laptop (Windows 11 on ARM64, native Claude
Code, Git for Windows, GitHub CLI). Planning notes that must stay private are kept
in a separate local folder, never in this repository.

### 1.4 Network

- **vmbr0:** trunk carrying VLANs to the integrated NIC and on to an access point
  in AP mode.
- **vmbr1 / vmbr2:** one Intel port per WAN.
- **WAN1:** fibre, PPPoE, primary, CGNAT.
- **WAN2:** cellular, DHCP, backup, likely CGNAT.
- **Gateway group `failover`:** Tier 1 = fibre, Tier 2 = cellular.
- **Domain** `ebisu.media`, managed at Cloudflare.

| Segment | VLAN tag | Role |
| --- | --- | --- |
| Management | untagged | Hypervisor management, AP, break-glass |
| DMZ | 10 | Public-facing apps |
| TRUST | 20 | Trusted users |
| Security | 30 | MCP servers, SIEM, automation (formerly `Virtual`, repurposed) |

### 1.5 Firewall, starting point

- **WAN / cellular:** no inbound pass rules (correct for CGNAT).
- **TRUST and management:** broad reach to every segment and the internet.
  Tightened in Phase 3.
- **DMZ and Security:** default-deny, no pass rules, not yet in use.

### 1.6 Planned second node

A second Proxmox host is planned for gaming, emulation and Home Assistant. It is
**standalone and never clustered** (a two-node cluster would lose quorum whenever it
is powered off), and it is powered on only when needed; `olympus` stays the always-on
node. OpenTofu manages the two nodes as separate endpoints.

It is not part of the active plan. Planning for it, including any storage changes on
`olympus`, starts once the active plan is complete and the hardware has arrived.

---

## 2. Target architecture

### 2.1 Ingress and identity

- **Cloudflare Tunnel** is the only ingress. The only published service in the active
  plan is the media server (Jellyfin).
- **Authentication is on hold.** Every system uses local accounts for now: Proxmox
  (`root`/PAM), OPNsense and Jellyfin. The edge gate and identity provider below are
  designed but deferred, to be added gradually (Phase 6).
  - **Known, accepted exposure:** until the edge gate returns, Jellyfin's login page
    is publicly reachable through the tunnel. Mitigation: strong unique passwords and
    no admin account used for streaming.
- **Planned, on hold (Phase 6):**
  - **Cloudflare Access** in front of every published hostname. Frontend apps: Google
    login plus an email allow-list. Backend/admin: a tighter allow-list federated to
    the IdP.
  - **WorkOS AuthKit (hosted)** as the first IdP: no local RAM cost, OIDC for Proxmox
    and Access.
  - **Authentik (self-hosted), deferred further.** Adopted only when OPNsense admin
    should sit behind the IdP (OPNsense needs LDAP, which WorkOS does not expose).
    Roughly 2 GiB across three containers.
- **Local accounts stay** even after identity is added.
- **Break-glass.**
  1. Local admin account on every backend.
  2. **Physical:** a direct cable from the admin laptop to the Proxmox management
     port, static address in range.
  - **Known limit:** if OPNsense is down, no remote path exists. Every segment, both
     WANs and the AP route through it. WireGuard is not viable here because CGNAT
     blocks inbound connections.
  - **Mitigation:** write tools use timed auto-revert (Phase 2). A remote fallback
     is re-evaluated once the tunnel exists (Phase 4).

### 2.2 DNS: split horizon

One naming scheme, two answers for `*.ebisu.media`.

- **Off-LAN:** public Cloudflare DNS, resolving to the tunnel.
- **On-LAN:** OPNsense Unbound returns internal addresses via host overrides, so
  local traffic never hairpins out. Every DHCP scope hands out OPNsense as DNS.

### 2.3 Secrets

- **Bitwarden Secrets Manager** in a separate free organisation. Free tier: unlimited
  secrets, 2 users, 3 projects, 3 machine accounts.
- Injected at deploy time with `bws`; never written to disk in plaintext.
- Rate limit is about 5 requests/second, so the loader batches reads
  (`bws secret list` per project) and caches in a state file.
- **Machine accounts (fits the cap):** `mcp-layer` (MCP downstream tokens),
  `iac-deploy` (OpenTofu and deploy secrets, including the real IP schema), `apps`
  (application runtime secrets).
- **IP schema:** the repo commits `ip-schema.example.yaml` (real structure, dummy
  values). The real file is a Bitwarden secret pulled at deploy.

### 2.4 Infrastructure as code

- **OpenTofu** (bpg/proxmox provider) for VMs, containers, storage and resource
  mappings. The same codebase can drive Cloudflare and DNS resources.
- **In-guest config:** cloud-init plus versioned Compose (or Podman Quadlet)
  manifests. Ansible only if in-guest config becomes painful.
- **OPNsense:** a versioned, **sanitized** `config.xml` with a scripted restore, as
  Deciso ships no first-class Terraform provider. Rules and aliases are also
  reachable through the OPNsense API that the MCP server wraps.
- **Raw `config.xml` never enters the repo.** It contains password hashes and keys.
  Only a sanitized copy, named differently, is committed.

### 2.5 MCP layer (agentic access)

- **Two servers.** OPNsense first, with read tools and a narrow set of guarded write
  tools. Proxmox second, read-only.
- Each exposes **named, audited tools**, not API passthrough. Every call is logged.
- **Write tools** apply with a timer and revert on their own unless confirmed, then
  export a sanitized config diff and commit it. This is the only path for OPNsense
  changes (Principle 9).
- **Run model:** a local Claude client on the admin laptop reaches the servers over
  the LAN. They are **LAN-only** and are not exposed through the tunnel until
  authentication returns (Phase 6). Client location does not change model quality.
- If automation (n8n, on hold) is added later, it reuses the same gateway endpoints.
- **Performance gate (Phase 5):** every tool call logs duration, response size and
  success. The numbers are reviewed before anything later is built. No SIEM is
  needed for this.

### 2.6 Monitoring and automation (on hold)

> **On hold.** The design below is kept for later; nothing here is scheduled.

- **SIEM: Wazuh.** Built-in ruleset and an agent model that fits later endpoint
  monitoring. Indices on the NVMe, about one month of retention. RAM is budgeted
  from measured numbers after the Phase 5 gate, not estimated.
- **Scope v1:** OPNsense firewall logs, Suricata alerts, Proxmox auth and audit
  logs. No NetFlow.
- **SOAR: n8n**, placed in the Security segment because it will hold write power.
  Example flow: Wazuh alert, then an OPNsense MCP block, then a notification.

### 2.7 Repository and working context

- **Public, MIT-licensed**, intended as a portfolio and as a reproducible reference.
- **Private working context** (decisions log, inventory, real addresses) lives
  outside the repo and is never committed. A sanitized agent-instructions file may
  be added to the repo later.
- **Knowledge tooling:** plain files first. A code-graph tool (Graphify) is added
  once real code exists, and kept only if a measured comparison shows it lowers
  token cost.
- Future non-public projects go in a separate repository.
- **Diagrams** live in `docs/` and carry no addresses.

---

## 3. Phase 0: Repository, workstation and secrets

**Intent:** the repo, licence, admin workstation and secret-injection mechanism
exist before anything else is built.

1. `[x]` Admin workstation set up: Git, GitHub CLI, Claude Code (native ARM64).
2. `[x]` Public repo created with MIT `LICENSE`, `README.md`, `.gitignore`
   (state, env, keys, raw `config.xml`, private context) and `.gitattributes` (LF).
3. `[ ]` Add this document and the directory skeleton:
   ```
   /docs       architecture, diagrams, runbooks
   /tofu       OpenTofu root and modules
   /compose    per-service Compose / Quadlet
   /opnsense   sanitized config export and restore notes
   /mcp        Proxmox and OPNsense MCP servers
   /schema     ip-schema.example.yaml
   /scripts    bootstrap and deploy helpers
   ```
4. `[ ]` Add a pre-commit secrets scan (for example gitleaks) and a CI check.
5. `[ ]` Create the Bitwarden free organisation and enable Secrets Manager.
6. `[ ]` Create the three machine accounts and projects. Store their tokens only in
   the password vault.
7. `[ ]` Write `scripts/load-secrets.sh` (state file, batched reads).
8. `[ ]` Author `schema/ip-schema.example.yaml`. Store the real file as an
   `iac-deploy` secret and confirm the loader materialises it locally only.
9. `[x]` Data-flow and topology diagrams added to `/docs`.

**Exit:** a clean clone plus `load-secrets.sh` reproduces the real IP schema from
Bitwarden, the secrets scan passes, and nothing secret is tracked.

---

## 4. Phase 1: Proxmox as code and host hygiene

**Intent:** bring the hypervisor under OpenTofu before building on it.

1. `[ ]` Snapshot `hermes` and `fafnir`; remove VM 104.
2. `[ ]` Create a least-privilege Proxmox API token for `iac-deploy` (VM, container
   and storage management only). Store it in Bitwarden.
3. `[ ]` Stand up the OpenTofu root and import existing guests (`tofu import`).
4. `[ ]` Codify storage, bridges (vmbr0/1/2) and the existing USB and PCI resource
   mappings.
5. `[ ]` Confirm `tofu plan` is clean against the live node.

**Exit:** `tofu plan` shows no unexpected diff and the host is fully described in
`/tofu`.

---

## 5. Phase 2: OPNsense MCP (read and guarded write)

**Intent:** every OPNsense change flows through an audited, reversible tool, so this
comes before any segmentation work. The server runs on the existing management
segment (which already has the reach it needs) and is used from the admin laptop on
the LAN. It stays LAN-only throughout the active plan.

1. `[ ]` **Maintenance exception.** Check the OPNsense version and API coverage
   (firewall rules and aliases, DHCP, Unbound, interfaces). Upgrade firmware first if
   coverage is missing. Take a configuration backup before any upgrade.
2. `[ ]` **Maintenance exception.** Enable the API and create a scoped user and key
   for the MCP server. Store it in Bitwarden (`mcp-layer`).
3. `[ ]` Deploy the OPNsense MCP as its own non-root service on the management
   segment, with secrets from `bws` at start.
4. `[ ]` **Read tools:** `list_rules`, `list_aliases`, `interface_status`,
   `gateway_status`, `service_status`, DHCP and DNS options.
5. `[ ]` **Narrow write tools:** create, update and delete a rule or alias, and set
   DHCP DNS options. Every write takes a change description, applies with a timer
   that **auto-reverts unless confirmed**, then exports a sanitized config diff and
   commits it.
6. `[ ]` Log every call: tool, duration, response size, success.
7. `[ ]` **Revert test.** Apply a deliberately bad but harmless change and confirm it
   rolls back on its own without touching the cable. Confirm the direct-cable path
   still works.
8. `[ ]` Connect a local Claude client from the admin laptop; verify the read tools
   and one reversible write.

**Exit:** a rule change can be made, reverted and committed through the tool alone,
and the revert path is proven.

---

## 6. Phase 3: Network segmentation (through the MCP)

**Intent:** replace broad TRUST and management reach with least-privilege rules and
bring DMZ and Security into service. All changes use the Phase 2 tools. If a needed
change is not exposed by the OPNsense API, extend the tooling and record the gap.
The UI is not used.

### Target inter-segment intent

| From \ To | Mgmt | DMZ | TRUST | Security | WAN |
| --- | --- | --- | --- | --- | --- |
| **Mgmt** | n/a | no | no | admin only | yes |
| **DMZ** | no | n/a | no | no | limited |
| **TRUST** | no | yes | n/a | yes | yes |
| **Security** | scoped | scoped | no | n/a | yes |

1. `[ ]` Confirm the table above, then implement it as MCP-applied changes.
2. `[ ]` Tighten management and TRUST from broad reach to the table.
3. `[ ]` Bring DMZ and Security into service with explicit pass rules. Security is
   reachable only from TRUST and management.
4. `[ ]` Verify every DHCP scope hands out OPNsense as DNS (management already does).
5. `[ ]` Redeploy the OPNsense MCP into the Security segment (via OpenTofu) and remove
   its temporary management-segment rules.
6. `[ ]` Confirm each change landed as a committed, sanitized export in `/opnsense`.

**Exit:** segmentation matches the table, the MCP lives in Security, and every change
is in git.

---

## 7. Phase 4: Split DNS and tunnel

**Intent:** the same names resolve internally to LAN addresses and externally through
the tunnel. Configuration changes use the MCP or deploy tooling.

1. `[ ]` Migrate Cloudflare DDNS off the legacy plugin to the supported one.
2. `[ ]` Create Unbound host overrides for each `app.ebisu.media`.
3. `[ ]` Publish public DNS records pointing at the tunnel, per hostname, as each
   service is deployed (the first is Jellyfin, milestone G1).
4. `[ ]` Install `cloudflared` in the DMZ; keep tunnel and hostname definitions in the
   repo.
5. `[ ]` Verify one name resolves internally on-LAN and via the tunnel off-LAN, using a
   throwaway test page that is removed afterwards.
6. `[ ]` **Re-evaluate remote break-glass** now that the tunnel exists (for example a
   second connector). Record the decision before continuing.

**Exit:** split horizon verified from both sides, tunnel config in git.

---

## 8. Phase 5: Proxmox MCP (read-only) and performance gate

**Intent:** the second server, plus a measured review of both before anything else
depends on them.

1. `[ ]` **Proxmox MCP (read-only):** `list_vms`, `vm_status`, `node_health`,
   `list_storage`, `task_log`, backed by a read-only API token.
2. `[ ]` Run it as its own non-root service in the Security segment, secrets from
   `bws`, every call logged.
3. `[ ]` Keep both MCP servers **LAN-only**, each with its own token auth. Nothing is
   published through the tunnel.
4. `[ ]` Connect a local Claude client from the admin laptop over the LAN. Use the
   live guests and the stopped `fafnir` VM as read targets and record what the tools
   can and cannot answer.
5. `[ ]` **Gate review:** compare logged latency, payload sizes, failure rates and
   revert behaviour against what later phases will need. Proceed only after review.

**Exit:** both servers answer through audited tools, the gate numbers are recorded in
`/docs`, and Proxmox cannot be mutated.

---

## 9. Milestone G1: Jellyfin media server

**Intent:** the first service, deployed only after both MCP servers exist, so every
firewall change goes through the audited tooling and the guest is described in code.

**Starts when:** Phase 2 and Phase 5 are done.

1. `[ ]` Define the Jellyfin guest in OpenTofu, in the DMZ. Decide between a VM and a
   container (open decision 7).
2. `[ ]` Create the DMZ rules through the OPNsense MCP: the tunnel connector reaches
   Jellyfin, Jellyfin reaches only what it needs outbound, and nothing in the DMZ
   reaches Management, TRUST or Security.
3. `[ ]` Deploy `cloudflared` in the DMZ and point one hostname at Jellyfin. Keep the
   tunnel definition in the repo.
4. `[ ]` Add the Unbound host override so LAN clients resolve the same name internally.
5. `[ ]` Set up Jellyfin local accounts: strong unique passwords, an admin account that
   is not used for streaming, and one account per household member.
6. `[ ]` Record the accepted exposure: the login page is publicly reachable until the
   edge gate returns (Phase 6).
7. `[ ]` Confirm each change landed as a committed, sanitized export in `/opnsense`.

**Exit:** household members stream from inside and outside the LAN using the same
name, and the exposure and its mitigation are documented.

---

## 10. Phase 9: Remaining write tools

**Intent:** extend write access beyond OPNsense rules only once the pipeline is
measured and trusted, one tool at a time.

1. `[ ]` Add Proxmox write tools behind a separate, higher-privilege token, one at a
   time (for example `vm_start`, `vm_stop`).
2. `[ ]` Keep the auto-revert and commit-per-change behaviour on every write tool.
3. `[ ]` Add `opnsense_block_ip` as a manually invoked tool. Wiring it to automated
   detection is on hold (Phase 8).
4. `[ ]` Keep destructive actions on the audited deploy path (OpenTofu), never ad hoc.

**Exit:** each write tool is audited, reversible where the platform allows, and lands
in git.

---

## 11. Phase 7: Retire fafnir (last step)

**Intent:** with the active plan complete, remove the already-stopped workstation VM
and reclaim its resources.

1. `[ ]` Back up anything needed from `fafnir` and take a final snapshot.
2. `[ ]` Remove the VM and its passthrough mappings through the audited path (open
   decision 8), then confirm in OpenTofu.
3. `[ ]` Record the freed vCPU and RAM in the capacity table.

**Exit:** `fafnir` is gone, its resources are free, and `tofu plan` is clean.

---

## 12. On hold: identity, security tooling and automation

These phases are designed but not scheduled. They are added gradually, at the pace of
the project, after the active plan. Until then every system uses local accounts.

### Phase 6: Identity (WorkOS and Cloudflare Access), on hold

**Intent:** hosted identity with no local RAM cost, wired into the two access tiers.

1. `[ ]` Create WorkOS AuthKit and configure Google as a social connection.
2. `[ ]` **Frontend gate:** Access app in front of Jellyfin (Google login and email
   allow-list). This closes the exposure recorded in G1.
3. `[ ]` **Backend gate:** Access app in front of the Proxmox UI and, only if remote
   access is wanted, the MCP hostnames (tight allow-list, federated to WorkOS via
   OIDC).
4. `[ ]` **Proxmox OIDC realm** against WorkOS; keep local `root`/PAM.
5. `[ ]` Confirm break-glass still works: local accounts and the direct cable.

**Exit:** household users sign in to Jellyfin with Google, admin reaches Proxmox
through IdP-gated SSO, and every break-glass path is verified.

#### Phase 6b: Authentik (deferred further)

`[ ]` Only when OPNsense admin should sit behind the IdP and RAM allows. Stand up
Authentik, expose its LDAP outpost to OPNsense, and re-point Proxmox and Access from
WorkOS.

### Phase 8: SIEM and SOAR, on hold

**Intent:** network-first visibility and automation, sized from measured numbers.

1. `[ ]` Build the RAM allocation table from the Phase 5 gate data and the freed
   capacity. Confirm Wazuh fits before deploying.
2. `[ ]` Enable Suricata/IDS on the relevant interfaces, as a change made through the
   OPNsense MCP.
3. `[ ]` Deploy Wazuh (single node) in the Security segment, indices on the NVMe,
   about one month retention.
4. `[ ]` Ship OPNsense firewall logs, Suricata alerts, Proxmox auth/audit logs and
   the MCP call logs.
5. `[ ]` Deploy n8n in the Security segment.
6. `[ ]` First SOAR flow, notify-only: Wazuh alert, then notification. Later, wire
   `opnsense_block_ip` into it.

**Exit:** baseline detections are visible and n8n reacts to alerts within the RAM
budget.

---

## 13. Security posture summary

- **Ingress:** zero inbound, tunnel only. The only published service is Jellyfin.
- **Identity (current):** local accounts everywhere, MCP servers LAN-only, physical
  last resort. Jellyfin's login page is public until the edge gate returns.
- **Identity (planned, on hold):** Cloudflare Access with Google for frontend, an
  IdP-federated tight allow-list for backend, local accounts retained.
- **Secrets:** Bitwarden Secrets Manager, deploy-time injection, scanned out of git.
- **Blast radius:** scoped tokens, narrow write tools with auto-revert, per-service
  isolation, Proxmox read-only until Phase 9, broader write behind a separate token.
- **Auditability:** MCP calls logged, mutations versioned in git.
- **Recoverability:** reproducible from the repo, sanitized configs captured.

---

## 14. Open decisions

| # | Decision | Default | Resolve in |
| --- | --- | --- | --- |
| 1 | OPNsense version and API coverage (upgrade needed?) | Check first | Phase 2 |
| 2 | Remote break-glass path | Physical only for now | Phase 4 |
| 3 | Authentik adoption (OPNsense LDAP) | On hold | Phase 6b |
| 4 | Wazuh RAM budget | On hold; built from measured data | Phase 8 |
| 5 | Graphify for code and docs | Measure after real code exists | Phase 5 onward |
| 6 | DNS on non-management DHCP scopes | Verify OPNsense is handed out | Phase 3 |
| 7 | Jellyfin guest type, media storage and transcoding | Decide at G1 | G1 |
| 8 | Mechanism for removing `fafnir` (a Phase 9 delete tool, or an OpenTofu apply) | Audited path, never ad hoc | Phase 7 |

---

## 15. Component reference

| Component | Choice | Licence / tier | Notes |
| --- | --- | --- | --- |
| Hypervisor | Proxmox VE 8.4 | AGPL | Single node `olympus` |
| Firewall | OPNsense | BSD | `hermes`, sanitized config.xml as code |
| Ingress | Cloudflare Tunnel | Free | Zero inbound |
| Edge gate (on hold) | Cloudflare Access | Free tier | Google and allow-list |
| IdP, first (on hold) | WorkOS AuthKit | Free tier | OIDC |
| IdP, later (on hold) | Authentik | Open source | OPNsense LDAP, about 2 GiB |
| Secrets | Bitwarden Secrets Manager | Free org | 3 projects, 3 machine accounts |
| IaC | OpenTofu | MPL | bpg/proxmox provider |
| In-guest | cloud-init, Compose or Quadlet | OSS | Ansible only if needed |
| MCP | Custom servers | MIT | OPNsense: guarded write with auto-revert; Proxmox: read-only |
| SIEM (on hold) | Wazuh | OSS | Indices on NVMe |
| SOAR (on hold) | n8n | Fair-code | Reuses the MCP gateway |
| Media server | Jellyfin | GPL | DMZ, local accounts for now |
| Admin workstation | `odysseus` | n/a | Windows 11 ARM64, native Claude Code |
| Repo | GitHub | MIT | IP schema via Bitwarden |
