# swap の暗号化
#
# agenix は秘密を /run/agenix/ へ復号する。/run は tmpfs であり、
# tmpfs のページは swap されうる。つまり復号済みの秘密が平文のまま
# ディスク上の swap パーティションへ書き出される可能性がある。
#
# systemd 自身がこの違いを明確に区別している。systemd credentials は
# credential を渡す際に tmpfs ではなく ramfs をマウントし、その理由を
# 「ramfs は swap されない」と明記した上で、保護状態を
#   secure (ramfs)  /  weak (それ以外のメモリ)  /  insecure
# と分類する。tmpfs 由来は "weak" にあたる。
#
# 起動ごとにランダム鍵で swap を暗号化すれば、電源断後にディスクを
# 読まれても復元できない。agenix の秘密だけでなく、Postgres のバッファや
# 各プロセスのメモリを含む「swap されうるすべて」に効く。
#
# 代償は hibernate ができなくなることだが、VPS なので無関係。

{ lib, ... }:

{
  # hardware-configuration.nix は nixos-generate-config が生成するファイルで
  # 「編集するな」と明記されているため、こちらで上書きする。
  #
  # デバイスの指定に by-partuuid を使うのは必須。NixOS には
  #
  #   You cannot use swap device "..." with randomEncryption enabled.
  #   The UUIDs and labels will get erased on every boot when the partition
  #   is encrypted.
  #
  # というアサーションがあり、by-uuid / by-label は弾かれる。dm-crypt が
  # パーティションの内容を上書きするため、swap 署名由来の UUID が毎回
  # 消えるのが理由。PARTUUID は GPT のパーティションテーブル側にあり、
  # 内容の暗号化では消えないので使える。
  swapDevices = lib.mkForce [
    {
      # /dev/sda3 (8G)。hardware-configuration.nix の by-uuid と同じ実体。
      device = "/dev/disk/by-partuuid/d262a0c2-40c8-47e0-9c72-4d240b20171e";
      randomEncryption.enable = true;
    }
  ];
}
