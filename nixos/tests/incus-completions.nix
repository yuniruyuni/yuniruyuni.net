{ pkgs, client }:
let
  postInstall = pkgs.writeText "incus-post-install.sh" client.postInstall;
in
pkgs.runCommand "incus-completion-regression" {
  nativeBuildInputs = [ pkgs.installShellFiles pkgs.strace ];
} ''
  mkdir -p "$out/bin"
  cat > "$out/bin/incus" <<'EOF'
  #!${pkgs.bash}/bin/bash
  exec ${pkgs.strace}/bin/strace -f -qq -o "$TMPDIR/incus-write.trace" \
    -e trace=write -e inject=write:delay_enter=100ms:when=1 \
    ${client}/bin/incus "$@"
  EOF
  chmod +x "$out/bin/incus"

  # Exercise the actual package hook with delayed first-run config writes.
  source ${postInstall}
  test -s "$out/share/bash-completion/completions/incus.bash"
  test -s "$out/share/fish/vendor_completions.d/incus.fish"
  test -s "$out/share/zsh/site-functions/_incus"
  bash -n "$out/share/bash-completion/completions/incus.bash"

  # A failed generator must fail the build, rather than hide its exit status
  # inside process substitution and merely produce an empty completion file.
  cat > "$out/bin/incus" <<'EOF'
  #!${pkgs.bash}/bin/bash
  if [ "$2" = fish ]; then exit 37; fi
  exec ${client}/bin/incus "$@"
  EOF
  export out
  set +e
  bash -e ${postInstall}
  generatorStatus=$?
  set -e
  test "$generatorStatus" -eq 37
  echo "Delayed configuration writes and generator failure propagation passed."
''
