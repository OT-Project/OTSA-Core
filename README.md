OTSA-Core
==========

OTSA-Core is the source tree for **OTSA** — the firmware/operating
system shipped on the **OT firewall appliance** of project
KC01.04-21.30, a multi-NIC mini-PC deployed at the OT/IT boundary to
protect Operational Technology (OT/ICS) networks.

The codebase is a hard-fork of the upstream
[OPNsense core](https://github.com/opnsense/core) project (FreeBSD-based
firewall framework), rebranded and re-scoped for OT-specific
deployments. Upstream remains the reference for the underlying
framework; this fork adds the appliance branding, Vietnamese
localization, a custom theme, a trimmed menu set, and OT-oriented
service defaults.

Where OTSA fits in the KC01.04-21.30 OT product line
----------------------------------------------------

The KC01.04-21.30 OT solution has two complementary software
components, each running on its own appliance:

| Component | Role | Hardware | Codebase | Forked from |
|-----------|------|----------|----------|-------------|
| **OTSA** *(this repo)* | Edge firewall — segments, filters and inspects traffic at the OT/IT boundary | Multi-NIC mini-PC | `OTSA-Core` | `opnsense/core` |
| **OTSC** | Central management & monitoring — collects telemetry, alerts and policy from OTSA appliances | Central server | `OT-SC-*` (separate repos) | `wazuh/wazuh` |

OTSA appliances are designed to interoperate with an OTSC central
node, but each codebase evolves independently. **This repository only
covers OTSA.**

Project identity
----------------

| Field | Value |
|-------|-------|
| Product | OTSA |
| Owner | KC01.04-21.30 — https://bkcs.hust.edu.vn |
| Maintainer | bkcs@hust.edu.vn |
| Package repository | http://192.168.150.49 |
| License | 2-Clause BSD (inherited from OPNsense) |
| Upstream | https://github.com/opnsense/core |

What's customized
-----------------

The fork diverges from upstream in the following areas. Files outside
these areas are generally upstream-managed and should be touched
conservatively to keep future syncs feasible.

* **Branding & build** — `Makefile`, `Mk/version.mk`,
  `Scripts/version.sh`, custom pkg repository config and signing
  fingerprints under `src/etc/pkg/`.
* **Localization** — full Vietnamese catalog at
  `src/share/locale/vi_VN/LC_MESSAGES/OPNsense.po` (web UI only; the
  console/shell scripts stay upstream English).
* **Theme** — two variants of the neobrutalist "OTSA 2.0" design with
  sidebar layout and KC01.04-21.30 branding, sharing the Slate palette
  and the `#2E8BC0` brand colour: `src/opnsense/www/themes/otsa/`
  (light, shipped as the default) and
  `src/opnsense/www/themes/otsa-dark/`.
* **Menu trim for OT** — entries across
  `src/opnsense/mvc/app/models/OPNsense/*/Menu/Menu.xml` are reduced
  and renamed:
  * "Destination NAT" → "Port Forward"
  * Kea menu items + service description → "DHCP Server"
  * WireGuard consolidated under the main VPN menu; OpenVPN hidden
  * "DNS Server" entry added under Unbound
* **SSH** — dedicated configuration page at
  `src/www/services_ssh.php`, per-user access management migrated
  onto the native `OPNsense/Auth/User` model, CIDR-based network
  restrictions, service control via `pluginctl`.
* **WireGuard** — controllers, forms and the general view reworked
  for OT site-to-site connectivity.
* **Services configured for OT** — NTP, DNS (Unbound), DHCP (Kea).
* **Console & shell scripts** under `src/opnsense/scripts/shell/` and
  the MOTD template, plus a custom `src/etc/ssh/sshd_config`.
* **Web GUI core** — significant rewrites in `src/www/interfaces.php`,
  `authgui.inc`, `system_advanced_admin.php`, and the layout partials
  that render the new menu and theme.
* **Design assets** — Penpot mockups `re-design.pen` and `ui.pen` at
  the repository root are the authoritative source for theme work.

Repository layout
-----------------

| Path | Purpose |
|------|---------|
| `src/etc/` | FreeBSD system configuration shipped with the appliance |
| `src/opnsense/mvc/` | PHP MVC application (models, controllers, views, forms) |
| `src/opnsense/www/themes/otsa{,-dark}/` | OTSA theme assets and compiled CSS |
| `src/opnsense/scripts/` | Console and service-side scripts |
| `src/www/` | Legacy PHP pages (firewall, interfaces, services) |
| `src/share/locale/vi_VN/` | Vietnamese translation catalog |
| `Mk/`, `Scripts/`, `Makefile` | Build system |
| `re-design.pen`, `ui.pen` | UI/UX mockups (Penpot) |
| `.context/git_conventions.md` | Mandatory commit-message rules |

Branches and workflow
---------------------

* `dev` — default integration branch; all feature PRs merge here.
* `staging` — pre-release validation.
* `main` — release branch.

Work happens on `feature/<area>` branches (e.g. `feature/ssh`,
`feature/vpn`, `feature/ntp`, `feature/dhcp`) and is merged into `dev`
through pull requests.

Commit conventions
------------------

Commit messages **must** follow `.context/git_conventions.md`:

```
<type>(<scope>): <imperative subject ≤72 chars, no period>

<motivation paragraph>

- Bullet describing change
- Bullet describing change
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`,
`test`, `chore`, `ci`, `security`, `revert`, `merge`. Use `!` after
the scope and a `BREAKING CHANGE:` footer for incompatible changes.
Subject and body are always written in English.

Build
-----

The build system is inherited from upstream OPNsense; see
https://docs.opnsense.org/development/architecture.html for the
underlying architecture and https://github.com/opnsense/tools for the
image-build toolchain. The resulting image is meant to be flashed
onto the firewall mini-PC hardware.

Common Makefile targets:

* `make package` — build a package from the current tree. Useful
  options include `CORE_PRODUCT`, `CORE_PACKAGESITE`,
  `CORE_MAINTAINER`, `CORE_NAME`. Defaults are set in `Makefile` and
  `Mk/version.mk` to OTSA/KC01.04-21.30 values — do not revert them to
  OPNsense defaults.
* `make update` — pull the latest commits on the current branch from
  the configured remote.
* `make upgrade` — build the package and replace the installed one.
* `make collect` — pull changes back from a running system for known
  files.
* `make lint` — syntax checks; run before opening a PR.
* `make style` — PSR-12 (PHP) and PEP-8 (Python) style checks.
* `make sweep` — run automatic sanitizers across the codebase.

For day-to-day development, an OPNsense VM with the `os-debug` plugin
installed gives the most convenient environment.

Contributing
------------

Internal contributions go through GitHub PRs against `dev`. Before
opening a PR:

1. Make sure your branch is named `feature/<area>` or `fix/<area>`.
2. Run `make lint` and `make style`.
3. Verify your commit messages match `.context/git_conventions.md`.
4. Reference the design (`re-design.pen` / `ui.pen`) when proposing
   UI changes.

License
-------

OTSA-Core inherits the 2-Clause BSD license from upstream OPNsense
(see `LICENSE`). All contributions to this fork must be licensed under
the same terms.
