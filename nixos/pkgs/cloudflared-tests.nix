# Reject invalid WebSocket types without racing unread payloads and Close.
# Keep the package version, runtime code, and all upstream tests unchanged.
final: prev:
{
  cloudflared = prev.cloudflared.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./cloudflared-websocket-test.patch ];
    postCheck = (old.postCheck or "") + ''
      go test -mod=vendor -count=1000 -timeout=120s \
        -run '^TestRead(Client|Server)Event_InvalidWebSocketMessageType$' ./management
    '';
  });
}
