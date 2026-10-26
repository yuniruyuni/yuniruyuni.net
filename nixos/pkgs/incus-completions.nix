# Incus 7.0.1 writes its initial config with create/truncate followed by write.
# Parallel completion processes can read the temporary empty config.yml.
# Keep this client-only workaround until Nixpkgs serializes generation or
# upstream makes first-run configuration creation safe for concurrent readers.
final: prev:
{
  incus-lts = prev.incus-lts.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      client = prev.incus-lts.client.overrideAttrs {
        postInstall = ''
          completionDir="$(mktemp -d)"
          export INCUS_CONF="$completionDir/config"
          export INCUS_CACHE="$completionDir/cache"
          export INCUS_GLOBAL_CONF="$completionDir/global"
          mkdir -p "$INCUS_CONF" "$INCUS_CACHE"

          # Ordinary files make generator failures visible to the build shell,
          # unlike process substitution, and avoid racing first-run SaveConfig.
          for completionShell in bash fish zsh; do
            "$out/bin/incus" completion "$completionShell" > "$completionDir/incus.$completionShell"
          done
          installShellCompletion --cmd incus \
            --bash "$completionDir/incus.bash" \
            --fish "$completionDir/incus.fish" \
            --zsh "$completionDir/incus.zsh"
        '';
      };
    };
  });
}
