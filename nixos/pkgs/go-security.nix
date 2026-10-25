# Keep the existing Nixpkgs package versions, while rebuilding Go programs with
# the crypto/x509 security release (GO-2026-6809 / CVE-2026-111943).
# Remove this overlay when the locked Nixpkgs Go 1.26 compiler is at least 1.26.10.
final: prev:
let
  patchedGo = prev.go_1_26.overrideAttrs (old: {
    version = "1.26.10";
    src = prev.fetchurl {
      url = "https://go.dev/dl/go1.26.10.src.tar.gz";
      hash = "sha256-/WPog7ovK/ypPBZGsx6+9j4rHk0rMXyXidl2po2B828=";
    };
  });
in
{
  go_1_26 = patchedGo;
  go = patchedGo;
  buildGo126Module = prev.buildGo126Module.override { go = patchedGo; };
  buildGoModule = prev.buildGoModule.override { go = patchedGo; };
}
