{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, zlib
}:

# Upstream ships a native addon (`node-addon-require-builtin`) that locates
# V8 internals by scanning the Node binary itself. It only recognizes the
# official Node.js builds, so the nixpkgs Node.js package cannot be used.
let
  inherit (stdenv.hostPlatform) system isLinux;
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  pin = sources.node.${system} or (throw "dsh: no official Node.js build for ${system}");
in
stdenv.mkDerivation {
  pname = "nodejs-official";
  version = sources.node.version;

  src = fetchurl { inherit (pin) url hash; };

  nativeBuildInputs = lib.optionals isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals isLinux [ stdenv.cc.cc.lib zlib ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a . $out/
    patchShebangs $out/bin $out/lib/node_modules
    runHook postInstall
  '';

  meta = {
    description = "Official Node.js runtime (upstream binaries, required by dsh)";
    homepage = "https://nodejs.org";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "node";
  };
}
