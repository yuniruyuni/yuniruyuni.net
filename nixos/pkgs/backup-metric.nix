# バックアップが成功した事実を、計測基盤が読める形で残す。
#
# 見張るのは「失敗した」ではなく「成功していない」。失敗を見ると、そもそも
# 動かなかった場合 (timer が止まった、script が消えた) を取りこぼす。最後に
# 成功した時刻だけを置いておけば、どの経路で途絶えても同じように現れる。
#
# 名乗る名前に job は使えない。Prometheus は取り込み側のジョブ名で job を
# 上書きするので、全部のバックアップが 1 系列に潰れて互いを隠してしまう。
# 実機で job="postgresql" が job="node" に化けることを確認した。
#
# 呼ぶのは systemd の ExecStartPost。ExecStart が 0 で終わったときにしか
# 実行されないので、成功の判定を自前で書かなくてよい。バックアップ本体の
# script には手を入れない。
{ pkgs }:

pkgs.writeShellScriptBin "backup-metric" ''
  set -euo pipefail

  if [ $# -lt 2 ]; then
    echo "usage: backup-metric <置き場> <名前>" >&2
    exit 2
  fi
  dir=$1
  job=$2

  # 計測基盤が無いホストでは何もしない。バックアップは計測に依存しない。
  if [ ! -d "$dir" ]; then
    exit 0
  fi

  # 別名で書いてから移す。node exporter は *.prom を随時読むので、
  # 書きかけを見せると途中までの行を取り込んでしまう。.tmp は読まれない。
  tmp="$dir/backup-$job.prom.tmp"
  {
    echo "# HELP yunirun_backup_last_success_seconds バックアップが最後に成功した時刻"
    echo "# TYPE yunirun_backup_last_success_seconds gauge"
    echo "yunirun_backup_last_success_seconds{backup=\"$job\"} $(${pkgs.coreutils}/bin/date +%s)"
  } > "$tmp"
  # 書くのは root、読むのはコンテナの非 root。
  ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
  ${pkgs.coreutils}/bin/mv -f "$tmp" "$dir/backup-$job.prom"
''
