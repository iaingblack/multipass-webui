# Multipass WebUI

A web-based management interface for [Canonical Multipass](https://multipass.run/). Runs on the same machine as Multipass and provides a browser UI + REST API for managing virtual machines.

Modelled on the Proxmox/vSphere UI pattern: a tree sidebar for navigation, tabbed detail views, and a dashboard overview. A **Ruby on Rails** rewrite of the original Go single-binary project.

## Features

### VM Management
- Create, start, stop, suspend, delete, recover instances from the browser
- Clone VMs
- Resize CPU/memory/disk on existing VMs
- Async launch with live progress tracking

### Dashboard & Monitoring
- Host resource cards (CPU load, memory, disk) with sparkline history
- VM status counts — running, stopped, suspended, deleted
- Bulk actions — Start All, Stop All, Purge Deleted

### Web Terminal
- Browser-based shell access via xterm.js + ActionCable
- Persistent PTY sessions — survive page refreshes with 64KB scrollback replay
- Resize handling (5-byte in-band prefix protocol)

### Cloud-Init Templates
- Built-in templates (Docker, web server, dev essentials, VNC-ready agent, etc.)
- Custom templates with full CRUD
- CodeMirror 6 YAML editor with syntax highlighting, real-time linting, indent guides

### Ansible Integration
- Playbook management — create, edit, store playbooks in the browser
- Inventory generation for your VMs
- Run playbooks with SSE-streamed terminal output

### Launch Profiles
- Save VM configurations as reusable profiles
- One-click launch from saved profiles

### Scheduled Operations
- Schedule VM start/stop or playbook runs at specific times/days
- Cron-like with execution history

### AI Chat Assistant (Phase 5 — coming soon)
- LLM-powered management via natural language
- Tool-calling agent with 24+ tools
- Works with OpenAI-compatible providers (OpenRouter, Ollama, Vercel AI Gateway)

### API & Automation
- REST API covering all VM, snapshot, mount, cloud-init, ansible, profile, schedule operations
- API tokens — persistent Bearer tokens for external automation
- Webhooks — HTTP POST notifications on events, with HMAC-SHA256 signing

### Audit & Observability
- Event log — persistent audit trail with filtering by category/actor/time

## Quick Start (production — Linux with multipass installed)

```bash
git clone https://github.com/iaingblack/multipass-webui.git
cd multipass-webui
sudo bin/install
```

This installs the app under `/opt/multipass-webui`, sets up two systemd services (`multipass-webui` for Puma, `multipass-webui-worker` for SolidQueue background jobs), and configures nginx as a reverse proxy.

The UI is available at `http://<your-server>:3000`. Default login is `admin` / `admin`. Configure via the Settings panel.

### Why systemd (not Docker)?

Multipass talks to its daemon via a Unix socket (`/var/snap/multipass/common/data/multipassd.socket`). That socket doesn't reliably cross the Docker boundary — snap confinement often blocks container access, and macOS Docker Desktop runs in its own VM where the host's multipassd is unreachable. systemd deployment matches the original Go app's deployment pattern and sidesteps these issues entirely.

### Uninstall

```bash
sudo bin/uninstall
```

### Service management

```bash
sudo systemctl restart multipass-webui multipass-webui-worker  # restart after update
sudo systemctl status multipass-webui                          # check status
sudo journalctl -u multipass-webui -f                          # follow Puma logs
sudo journalctl -u multipass-webui-worker -f                   # follow worker logs
```

## Development

Requires Ruby 3.3+, Node.js 20+, and `multipass` installed locally.

```bash
git clone https://github.com/iaingblack/multipass-webui.git
cd multipass-webui
bundle install
npm install
bin/rails db:prepare
bin/dev    # runs Puma + JS/CSS watchers via foreman
```

Open `http://localhost:3000`. Default login: `admin` / `admin`.

### Running tests

```bash
bundle exec rspec                       # full suite
bundle exec rspec spec/services/        # multipass wrapper unit tests (125 cases)
bundle exec rspec spec/requests/        # auth + controllers
bundle exec rubocop                     # Ruby style
```

## Tech Stack

- **Backend:** Ruby on Rails 8.1 (Hotwire, Turbo, Stimulus, ActionCable)
- **Database:** SQLite via ActiveRecord
- **Background jobs:** SolidQueue (DB-backed, no Redis dependency)
- **Real-time:** ActionCable (Redis pub/sub adapter for terminals/chat)
- **Frontend:** Hotwire (Turbo Drive + Frames + Stimulus) + Tailwind CSS v4
- **Terminal:** xterm.js over ActionCable
- **Editor:** CodeMirror 6 (YAML lang + lint)
- **Icons:** Lucide
- **Multipass interaction:** `Open3.capture3` with dual-layer name validation
  (HTTP boundary + service layer) to prevent flag injection

## Architecture

```
Browser ──HTTP──▶ nginx ──▶ Puma (Rails app) ──▶ Multipass::Client ──exec──▶ multipass CLI
                  │                              ──▶ ActiveRecord (SQLite)
                  │                              ──▶ Event log
                  └─WS──▶ ActionCable ──▶ TerminalChannel ──PTY──▶ multipass shell <vm>
                                       ──▶ ChatChannel     ──▶ LLM provider
                                       ──▶ AnsibleRunChannel ──▶ ansible-playbook

systemd:
  multipass-webui.service          → bin/rails server
  multipass-webui-worker.service   → bin/jobs (SolidQueue: terminals, sched, webhooks)
```

## Migrating from the Go version

A `rails db:migrate_from_go_config[path]` task reads the existing Go `~/.passgo-web/config.json` + `events.jsonl` and imports them into the SQLite DB. Bcrypt password hashes port directly.

## Project status

Phase 0–4, 6, 7 (partial) complete. Phase 5 (LLM chat) and Phase 8 (terminal integration with full UI) in progress.

See `PLAN.md` for the full phased plan and current status.

## License

MIT
