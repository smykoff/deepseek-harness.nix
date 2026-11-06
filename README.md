English | [Русский](README.ru.md)

# deepseek-harness.nix

Nix flake that packages [DeepSeek Harness (`dsh`)](https://github.com/deepseek-ai/deepseek-harness) — the CLI and the Web UI.

The package installs the official npm release `@deepseek-ai/dsh` together with the official Node.js runtime, and exposes a single `dsh` binary.

## Why the npm release and not a GitHub release archive

Every release in [deepseek-ai/deepseek-harness/releases](https://github.com/deepseek-ai/deepseek-harness/releases) is a tag without uploaded assets — the GitHub API reports `assets: 0`. The `tar.gz` shown under "Assets" is GitHub's auto-generated source snapshot of the tag: a ~39 MB, 23 112-file TypeScript pnpm monorepo with no build output, no `node_modules` and no native binaries. Using it would mean reproducing the whole upstream workspace build in the Nix sandbox.

`@deepseek-ai/dsh` is the official published build of the same release: compiled JS plus 90 `@deepseek-ai/dsh-*` dependencies, including prebuilt native addons for each platform (`node-addon-system-linux-x64`, `node-addon-require-builtin-linux-x64-gnu`, `node-pty`, `koffi`, `sharp`, …).

## Why an official Node.js build

`dsh` boots through `node-addon-require-builtin`, a native addon that looks up Node's internal module loader by scanning the running Node binary. The nixpkgs build is not recognized by it:

```
dsh: host preparation failed: node-addon-require-builtin unsupported: Unsupported/no-getter
  (x64 sysv getter is not a recognized this->field accessor)
```

The [nodejs.org](https://nodejs.org/dist) build of the same version starts normally. The runtime is therefore fetched from nodejs.org and pinned in `sources.json` (`node.version`, per-platform URL and hash). Do not replace it with `pkgs.nodejs_24` — the package will fail at boot.

## Why not Bun

Bun cannot run `dsh`. Two independent blockers:

1. The same `node-addon-require-builtin` addon needs Node/V8 internals. Under `bun 1.3.13` it fails with `No usable native binding found for node-addon-require-builtin-linux-x64-gnu`.
2. The storage backend (`@deepseek-ai/dsh-storage-sqlite`) imports `node:sqlite`, which Bun does not implement.

The `--version` flag answers under Bun, but any real profile boot fails. There is no wrapper switch for this; it would require upstream changes.

## Supported platforms

| System           | Status                                                              |
|------------------|---------------------------------------------------------------------|
| `x86_64-linux`   | upstream runtime verified manually, `nix build` not run to completion |
| `aarch64-linux`  | untested                                                            |
| `x86_64-darwin`  | untested                                                            |
| `aarch64-darwin` | untested                                                            |

## Usage

Run without installing:

```sh
nix run github:<REPO>
```

Install into the user profile:

```sh
nix profile install github:<REPO>
```

Start the Web UI (defaults to `http://127.0.0.1:3080`):

```sh
dsh web
```

### NixOS (flakes)

```nix
{
  inputs.dsh.url = "github:<REPO>";

  outputs = { nixpkgs, dsh, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [ dsh.packages.${pkgs.system}.default ];
        })
      ];
    };
  };
}
```

Or via the overlay:

```nix
nixpkgs.overlays = [ dsh.overlays.default ];
environment.systemPackages = [ pkgs.dsh ];
```

### Home Manager

```nix
home.packages = [ inputs.dsh.packages.${pkgs.system}.default ];
```

## Notes

- The wrapper puts `node`, `npm`, `npx` (from the pinned official Node.js), `bash`, coreutils, `git`, `openssh` and `which` on `PATH`, so plugin installation and the tool runtime work out of the box.
- Native addons are patched by `autoPatchelfHook`. The npm tree also ships binaries for other platforms, so `autoPatchelfIgnoreMissingDeps` is enabled.
- Install scripts are skipped (`--ignore-scripts`); every dependency is used through its prebuilt binary. `node-pty`'s `spawn-helper` executable bit is restored during install, as upstream does in a postinstall script.
- State lives in `$DSH_HOME` (default under your home directory), not in the Nix store.

### Downloaded binaries (Linux)

DSH downloads some components at runtime (for example the Office engine and the Python environment used by the Python SDK). On NixOS these need a dynamic loader compatibility layer:

```nix
programs.nix-ld.enable = true;
programs.nix-ld.libraries = with pkgs; [ stdenv.cc.cc.lib zlib openssl ];
```

## Updating

`sources.json` is the single source of truth: `version`, `npmDepsHash` and the Node.js runtime pins. `npm/package.json` plus `npm/package-lock.json` hold the exact dependency set.

```sh
bash scripts/update.sh                      # follow the npm `latest` tag
bash scripts/update.sh --node-version 24.x  # also repin the Node.js runtime
```

The script resolves the new version, regenerates the lockfile, derives `npmDepsHash` from the hash-mismatch error of a failed build, then builds the package. A scheduled workflow (`.github/workflows/update.yml`) runs it daily and commits the result.

The Node.js pin is intentionally manual: only the officially built binary is compatible with the native addon, and a new Node.js release may need to be verified before bumping.
