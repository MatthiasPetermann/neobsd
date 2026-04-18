# neobsd

Patch stack and build orchestration for NetBSD/NeoBSD targets.

This repository separates release intent (what to patch) from execution context (how and where to build).

## Core Model

- Target (`targets/<name>/`): defines the patch stack and pinned base source state.
- Profile (`profiles/<name>`): shell configuration consumed by `scripts/run-pipeline.sh`.
- Patch set (`patches/...`): actual patch payload grouped by one-letter set key.

In short:

- `targets/` answers: what are we building?
- `profiles/` answers: how are we building and publishing it?

## Repository Layout

```text
.
|- patches/                     # patch payloads
|- profiles/                    # pipeline profiles (shell files)
|- targets/                     # target definitions (base/commit/series)
|- scripts/                     # orchestrator + specialized helpers
`- README.md
```

Typical target layout:

```text
targets/neobsd-11/
|- base                         # e.g. netbsd-11
|- commit                       # pinned git commit in src repo
`- series                       # ordered patch entries
```

## Configuration Resolution

`scripts/run-pipeline.sh` resolves values in this order:

1. built-in defaults
2. profile file (`--profile <path>`)
3. CLI options (highest priority)

Auto profile loading:

- If `--profile` is omitted and `--target` is set, auto-load expects `profiles/<target>-<machine>-<machine-architecture>`.

## Path Strategy (Global Consistency)

The pipeline uses a single ordering strategy everywhere relevant:

- `target -> release-id -> platform-key`

Definitions:

- `target`: release line and patch stack identity, for example `neobsd-11`.
- `release-id`: technical run/release id, for example `26.2`.
- `platform-key`: `<machine>-<machine-architecture>`, or `<machine>` if arch is empty.

Path formulas:

- Object tree: `<obj-root>/<target>/<release-id>/<platform-key>/`
- Release payload source: `<object-tree>/releasedir/`
- Published destination (`PUBLISH_MODE=copy`): `<publish-dir>/<target>/<release-id>/<platform-key>/`
- Reusable tools (`REUSE_TOOLS=1`, no explicit `TOOLS_DIR`): `<tools-root>/<target>/<release-id>/<platform-key>/`

Important design decision:

- `base-name` (for example `netbsd-11`) is intentionally not part of the tools path.
- Reason: in this model, `target` already represents the full build identity (including applied patch stack). Keeping `base-name` in the tools path can look redundant or even misleading.
- `release-id` is part of the tools path to prevent accidental cross-release reuse of toolchains.
- For iterative development where you want tools reuse across multiple runs, set a stable `--release-id` explicitly.

## Included Profiles

Current profiles in this repository:

- `profiles/neobsd-11-amd64-x86_64`
- `profiles/neobsd-11-evbarm-earmv7`

Example resolved paths for `release-id=26.2`:

```text
Profile: neobsd-11-amd64-x86_64
  target       = neobsd-11
  platform-key = amd64-x86_64
  tools        = /build/tools/neobsd-11/26.2/amd64-x86_64
  obj          = /build/obj/neobsd-11/26.2/amd64-x86_64
  publish      = /dist/neobsd-11/26.2/amd64-x86_64

Profile: neobsd-11-evbarm-earmv7
  target       = neobsd-11
  platform-key = evbarm-earmv7
  tools        = /build/tools/neobsd-11/26.2/evbarm-earmv7
  obj          = /build/obj/neobsd-11/26.2/evbarm-earmv7
  publish      = /dist/neobsd-11/26.2/evbarm-earmv7
```

## Full Pipeline Flow (ASCII Sequence Diagrams)

### Flow Example: `neobsd-11-amd64-x86_64`

```text
Operator        run-pipeline.sh      prepare-repos.sh     apply-patches.sh     build-netbsd.sh      publish-artifacts.sh      Filesystem
   |                   |                    |                    |                    |                      |                    |
   |-- run --profile ->|                    |                    |                    |                      |                    |
   |                   |-- load profile --->|                    |                    |                      |                    |
   |                   |-- resolve -------> |                    |                    |                      |                    |
   |                   |   target=neobsd-11|                    |                    |                      |                    |
   |                   |   release=26.2    |                    |                    |                      |                    |
   |                   |   platform=amd64-x86_64                |                    |                      |                    |
   |                   |-- preflight obj --------------------------------------------------------------->   |                    |
   |                   |   /build/obj/neobsd-11/26.2/amd64-x86_64                                      |                    |
   |                   |-- stage: prepare --->|               (sync src/xsrc)            |                      |                    |
   |                   |<-- repos ready ------|                    |                    |                      |                    |
   |                   |-- stage: apply --------------------------->|  apply series      |                      |                    |
   |                   |<-- patches applied ------------------------|                    |                      |                    |
   |                   |-- stage: build ------------------------------------------------->|                      |                    |
   |                   |   obj=/build/obj/neobsd-11/26.2/amd64-x86_64                    |                      |                    |
   |                   |   tools=/build/tools/neobsd-11/26.2/amd64-x86_64                |                      |                    |
   |                   |<-- releasedir ready ---------------------------------------------|                      |                    |
   |                   |-- stage: publish --------------------------------------------------------------------->|                |
   |                   |                                                                 |-- copy releasedir ----------------------->|
   |                   |                                                                 |   /dist/neobsd-11/26.2/amd64-x86_64     |
   |                   |<-- done --------------------------------------------------------------------------------------------------------------------|
```

### Flow Example: `neobsd-11-evbarm-earmv7`

```text
Operator        run-pipeline.sh      prepare-repos.sh     apply-patches.sh     build-netbsd.sh      publish-artifacts.sh      Filesystem
   |                   |                    |                    |                    |                      |                    |
   |-- run --profile ->|                    |                    |                    |                      |                    |
   |                   |-- load profile --->|                    |                    |                      |                    |
   |                   |-- resolve -------> |                    |                    |                      |                    |
   |                   |   target=neobsd-11|                    |                    |                      |                    |
   |                   |   release=26.2    |                    |                    |                      |                    |
   |                   |   platform=evbarm-earmv7               |                    |                      |                    |
   |                   |-- preflight obj --------------------------------------------------------------->   |                    |
   |                   |   /build/obj/neobsd-11/26.2/evbarm-earmv7                                     |                    |
   |                   |-- stage: prepare --->|               (sync src/xsrc)            |                      |                    |
   |                   |<-- repos ready ------|                    |                    |                      |                    |
   |                   |-- stage: apply --------------------------->|  apply series      |                      |                    |
   |                   |<-- patches applied ------------------------|                    |                      |                    |
   |                   |-- stage: build ------------------------------------------------->|                      |                    |
   |                   |   obj=/build/obj/neobsd-11/26.2/evbarm-earmv7                   |                      |                    |
   |                   |   tools=/build/tools/neobsd-11/26.2/evbarm-earmv7               |                      |                    |
   |                   |<-- releasedir ready ---------------------------------------------|                      |                    |
   |                   |-- stage: publish --------------------------------------------------------------------->|                |
   |                   |                                                                 |-- copy releasedir ----------------------->|
   |                   |                                                                 |   /dist/neobsd-11/26.2/evbarm-earmv7    |
   |                   |<-- done --------------------------------------------------------------------------------------------------------------------|
```

## Quick Start

### 1) Define target metadata

Create:

- `targets/<target>/base`
- `targets/<target>/commit`
- `targets/<target>/series`

Example:

```text
targets/neobsd-11/base   -> netbsd-11
targets/neobsd-11/commit -> 1e7843549f865337fc095ab555d401dcad1702d7
```

### 2) Add patches and series entries

For a series entry like:

```text
c/0002-cells-core
```

expected patch path is:

- `patches/c/0002-cells-core/<base>.patch`

### 3) Create a profile

Example: `profiles/neobsd-11-amd64-x86_64`

```sh
TARGET="neobsd-11"

# Optional: build branding passed to netbsd build.sh
BUILD_BRAND_NAME="NeoBSD"
BUILD_ID_PREFIX="neobsd"

# Optional: identity used by git am while applying patches
GIT_COMMITTER_NAME="NeoBSD Builder"
GIT_COMMITTER_EMAIL="builder@builder.lan"

SRC_DIR="/build/netbsd-src"
XSRC_DIR="/build/netbsd-xsrc"

SRC_REPO="https://github.com/NetBSD/src.git"
XSRC_REPO="https://github.com/NetBSD/xsrc.git"
FETCH_MODE="auto"          # auto|none

MACHINE="amd64"
MACHINE_ARCHITECTURE="x86_64"
BUILD_STEPS="all"          # space-separated list or all
NO_X=0                      # 1/0

REUSE_TOOLS=1               # 1/0
TOOLS_ROOT="/build/tools"

OBJ_ROOT="/build/obj"

PUBLISH_MODE="copy"        # none|local|copy|script|rsync
PUBLISH_DIR="/dist"

# For PUBLISH_MODE="script":
# PUBLISH_SCRIPT="scripts/publish-hook-example.sh"
```

Notes:

- `NO_X=0` enables xsrc/X11 build flow (`--with-x`).
- `NO_X=1` disables xsrc/X11 build flow (`--no-x`).
- `BUILD_STEPS` accepts a space-separated list (`"release sourcesets"`), `all` expands to the default full sequence.
- `MACHINE_ARCHITECTURE` maps to `build.sh -a`.
- For `MACHINE=amd64`, use `MACHINE_ARCHITECTURE=x86_64`.
- `BUILD_BRAND_NAME` sets `BUILDINFO` for `build.sh` as `<brand> <release-tag-or-id>`.
- `BUILD_ID_PREFIX` sets `build.sh -B` as `<prefix>-<release-tag-or-id>`.
- If `BUILD_BRAND_NAME` or `BUILD_ID_PREFIX` are unset, pipeline does not pass those values to `build.sh`.
- If the selected object path already exists, preflight aborts unless `--clean` is set.

### 4) Validate series

```sh
scripts/validate-series.sh --target neobsd-11
```

### 5) Run pipeline

```sh
scripts/run-pipeline.sh --profile profiles/neobsd-11-amd64-x86_64
```

Override per run:

```sh
scripts/run-pipeline.sh \
  --profile profiles/neobsd-11-amd64-x86_64 \
  --release-tag 26.2 \
  --clean \
  --build-steps "release sourcesets" \
  --jobs 24
```

## Custom Publish Hook Interface

When `PUBLISH_MODE="script"` (or `--publish-mode script`) is used, the hook is executed without positional arguments. Pipeline context is passed via environment variables:

- `PIPELINE_SOURCE_DIR` (required)
- `PIPELINE_ARTIFACT_DIR` (deprecated alias)
- `PIPELINE_TARGET` (required)
- `PIPELINE_RELEASE_ID` (required)
- `PIPELINE_RELEASE_TAG` (optional)
- `PIPELINE_MACHINE` (optional)
- `PIPELINE_MACHINE_ARCHITECTURE` (optional)
- `PIPELINE_PLATFORM_KEY` (required)
- `PIPELINE_BASE_NAME` (optional)
- `PIPELINE_BASE_COMMIT` (optional)

Example hook:

- `scripts/publish-hook-example.sh`

## Release Tag vs Release ID

- `release_tag`: git tag label in format `YY.<sequence>` (for example `26.0`, `26.1`, `26.2`)
- `release_id`: technical id used in output directory layout

`scripts/run-pipeline.sh` resolves `release_tag`:

1. value from profile/CLI (`--release-tag`), if set
2. otherwise exact git tag at `HEAD`, if present

`release_tag` must match `YY.<sequence>`, sequence starts at `0`.

If `release_id` is not set:

1. `release_tag` is used (if present)
2. otherwise `dev-<utc-timestamp>-<shortsha>`

Build metadata (`BUILDINFO` / `-B`) uses `release_tag` when available, otherwise `release_id`.

## Patch Set Keys

Use one-letter directories under `patches/`:

- `a`: base/core userland foundations
- `b`: build system, CI, tooling
- `c`: cells/containers/runtime
- `k`: kernel, low-level drivers, hardware
- `n`: networking stack and services
- `p`: packaging, release assembly, publish flow
- `s`: security and hardening
- `u`: userland utilities and admin UX
- `x`: experimental
- `z`: local/private temporary work

## Series Validation Rules

`scripts/validate-series.sh` checks:

- entries are relative paths (no absolute paths, no `..`)
- no duplicate entries
- patch file exists as `<base>.patch`
- basename starts with `NNNN-` (default)
- numeric prefixes are non-decreasing (default)

Useful flags:

- `--check-prefix-order 0` to disable ordering checks
- `--require-prefix 0` to disable prefix requirement

## Script Reference

- `scripts/run-pipeline.sh`: top-level orchestrator
- `scripts/prepare-repos.sh`: clone/fetch/reuse `src` and `xsrc`
- `scripts/apply-patches.sh`: reset to base commit and apply patch stack
- `scripts/build-netbsd.sh`: wrapper around NetBSD `build.sh`
- `scripts/publish-artifacts.sh`: publish `obj/releasedir` (`none|local|copy|script|rsync`)
- `scripts/publish-hook-example.sh`: example hook for script publish mode
- `scripts/validate-series.sh`: validates target `series`

## Logging

- logs are written to `stderr`
- usage text and payload output are written to `stdout`
