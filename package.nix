{ lib
, stdenv
, fetchNpmDeps
, nodejs
, npmHooks
, makeWrapper
, autoPatchelfHook
, bashInteractive
, coreutils
, gnugrep
, gnused
, git
, openssh
, which
, zlib
  # Official Node.js build; see node.nix for why nixpkgs' nodejs is not usable.
, nodeRuntime
}:

let
  inherit (stdenv.hostPlatform) isLinux;
  sources = builtins.fromJSON (builtins.readFile ./sources.json);

  runtimePath = lib.makeBinPath [
    nodeRuntime
    bashInteractive
    coreutils
    gnugrep
    gnused
    git
    openssh
    which
  ];
in
stdenv.mkDerivation {
  pname = "dsh";
  version = sources.version;

  # `npm/` holds a pinned package.json plus the package-lock.json that
  # scripts/update.sh regenerates on every version bump.
  src = ./npm;

  nativeBuildInputs = [ nodejs npmHooks.npmConfigHook makeWrapper ]
    ++ lib.optionals isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals isLinux [ stdenv.cc.cc.lib zlib ];

  npmDeps = fetchNpmDeps {
    src = ./npm;
    hash = sources.npmDepsHash;
  };

  # Every dependency ships prebuilt binaries; install scripts would try to
  # rebuild or download them.
  npmRebuildFlags = [ "--ignore-scripts" ];

  dontBuild = true;
  dontStrip = true;

  # The tree contains native libraries for other platforms as well.
  autoPatchelfIgnoreMissingDeps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/dsh
    cp -a node_modules $out/lib/dsh/node_modules

    # node-pty strips the executable bit from its prebuilt spawn helper during
    # packing; upstream restores it in a postinstall script.
    find $out/lib/dsh/node_modules -name spawn-helper -type f -exec chmod +x {} +

    makeWrapper ${nodeRuntime}/bin/node $out/bin/dsh \
      --add-flags $out/lib/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js \
      --prefix PATH : ${runtimePath}

    runHook postInstall
  '';

  meta = {
    description = "DeepSeek Harness: an open-source agent harness built on an everything-is-a-plugin architecture";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "dsh";
  };
}
