# Synology helper extraction plan

Create a separate project that contains the reusable NAS helper workflow without any `balance`-specific commands or assumptions, while treating Synology as the primary target platform.

## Goal

- Extract the SSH + remote Docker helper patterns from `scripts/nas-helper.sh` into a standalone helper for Synology-hosted container workflows.
- Keep Synology-specific behavior explicit and configurable instead of scattering it through project-specific scripts.

## Scope for the new project

### Keep

- sync project files to remote host
- validate remote compose config
- build remote image/service
- run help/smoke/config commands remotely
- tail remote logs

### Remove

- service names like `balance` / `balance_apply`
- hardcoded plan/log paths specific to this repo
- Sonarr/Plex-specific commands
- TV/media-specific naming

## Recommended shape

1. New project structure
   - `scripts/nas-helper.sh` or renamed generic entrypoint
   - `Makefile`
   - `.env.example`
   - `README.md`
   - optional `config/` for per-project settings
2. Core abstractions
   - remote host/user
   - remote project directory
   - remote docker binary path
   - sync include list / rsync or scp strategy
   - generic service/compose command runner
3. Config model
   - `NAS_HOST`
   - `REMOTE_DIR`
   - `DOCKER_BIN`
   - `COMPOSE_FILE` or compose working dir
   - `DEFAULT_SERVICE`
4. Platform profile model
   - define a `PLATFORM=synology` default
   - centralize Synology-specific command paths and behaviors (for example Docker binary path, compose invocation quirks, common volume roots)
   - allow a later `generic-linux` profile without changing command semantics
5. Naming direction
   - prefer a name that admits the Synology bias, such as `synology-helper`, `synology-remote-helper`, or `synonas-helper`
   - avoid pretending it is fully generic if Synology assumptions are built in by default
6. Safe defaults
   - no destructive commands by default
   - no media- or app-specific behavior
   - commands should work even if a project only wants `sync`, `build`, `config`, `logs`

## Implementation phases

1. Identify reusable code in current `scripts/nas-helper.sh`
2. Split generic vs project-specific commands
3. Create new standalone repo/workspace for helper
4. Add config-driven command definitions
5. Write concise README and examples for adapting it to another project
6. Optionally re-consume it from `balance` later (copy, submodule, or template-based approach)

## Open design choices

- shell-only project vs shell + Makefile wrapper
- fixed built-in commands vs config-defined custom commands
- `scp`-based sync vs `rsync`-based sync
- standalone repo vs template repo

## Notes

- Synology should be the first-class target, not an accidental implementation detail.
- If broader Linux support is added later, it should come through a profile/config layer rather than by hardcoding more special cases into the helper.
- No extraction is being performed yet; this file is a design note for later work.
