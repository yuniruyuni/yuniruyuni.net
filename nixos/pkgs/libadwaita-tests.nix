# Keep one virtual display alive for the complete, parallel Meson test suite.
# Xvfb otherwise resets after its last client disconnects, racing the next test.
# Do not change runtime sources, enabled tests, concurrency, or failure handling.
final: prev:
{
  libadwaita = prev.libadwaita.overrideAttrs (old: {
    checkPhase =
      assert prev.lib.hasInfix "xvfb-run" old.checkPhase;
      prev.lib.replaceStrings
        [ "xvfb-run" ]
        [ "xvfb-run -s '-screen 0 640x480x24 -noreset'" ]
        old.checkPhase;
  });
}
