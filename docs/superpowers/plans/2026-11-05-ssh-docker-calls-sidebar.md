# SSH Docker Calls Sidebar Deployment Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a PowerShell script the operator can run locally to apply the calls-sidebar change to a compatible remote checkout over SSH and rebuild the Docker deployment.

**Architecture:** The script accepts an SSH target and a POSIX checkout path, transfers a narrow Git patch plus a Compose override, applies the patch only when it matches the remote source (or is already applied), builds a custom production image, then recreates only the Rails and Sidekiq services. It does not patch precompiled assets in a running container.

**Tech Stack:** PowerShell, OpenSSH (`ssh`/`scp`), Git, Docker Compose.

**Spec:** User request in this conversation: create a script that changes the calls sidebar through SSH on a Docker host.

## Global Constraints

- Do not store SSH credentials or secrets in the script.
- Apply only the calls-sidebar source change and stop if the remote source does not match the patch.
- Build assets through the repository Dockerfile; do not modify compiled JavaScript in a running container.
- Recreate only the `rails` and `sidekiq` services, keeping the existing production Compose configuration and data volumes.
- Do not add or run tests unless requested.

## Review Focus

- Missing SSH tools: fail before modifying the remote checkout.
- Incorrect remote directory or missing production Compose/Dockerfile: fail before applying the patch.
- Source version mismatch: fail without overwriting remote source.
- Already-applied patch: proceed with the build without applying it twice.
- Docker build or service update failure: return a nonzero status and preserve logs for rerun/diagnosis.

---

### Task 1: Remote Docker deployment helper

**Files:**
- Create: `docker/deploy_calls_sidebar_over_ssh.ps1`
- Create: `docker/patches/calls-sidebar.patch`
- Create: `docker/docker-compose.calls-sidebar.yaml`
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (already modified in the current task)

**Interfaces:**
- Script parameters: mandatory `SshTarget` (`user@host`) and `RemoteAppPath` (POSIX path to a Chatwoot source checkout).
- Remote deployment inputs: `docker-compose.production.yaml`, `docker/Dockerfile`, and the source checkout matching the patch.
- Result: production Rails and Sidekiq containers run from the rebuilt custom image.

- [ ] Create a narrowly scoped patch file from the current Sidebar change and a Compose override that builds a custom image for `rails` and reuses it for `sidekiq`.
- [ ] Implement the PowerShell SSH helper with argument validation, `ssh`/`scp` checks, remote path checks, patch applicability/idempotence handling, image build, and service recreation.
- [ ] Include a usage example and required remote-checkout assumptions in the script help text.
- [ ] Run `git diff --check` and inspect the final patch and script diff; do not run application tests.
