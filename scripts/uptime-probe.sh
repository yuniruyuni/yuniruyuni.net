#!/bin/bash
# VPS の外 (GitHub Actions) から公開ホスト名を叩いて生死を確かめる。
# .github/workflows/uptime.yml から呼ばれる。ローカルでもそのまま動く。
#
# 各ターゲットは「期待ステータス」と「本文に含まれるべき文字列」で判定する。
# ステータスだけ見ると、SPA の fallback (どのパスにも index.html を 200 で返す)
# や Cloudflare のエラーページを健康と取り違えるため。
#
# 一時的な揺れで騒がないよう、失敗したターゲットは RETRY_DELAY 秒おきに
# 最大 ATTEMPTS 回まで試す。ターゲットは並列に調べる。
#
# 出力:
#   - stdout と $GITHUB_STEP_SUMMARY (あれば) に結果表 (Markdown)
#   - $GITHUB_OUTPUT (あれば) に down=<落ちたターゲット名をカンマ区切り>
#   - 終了コードは常に 0 (判定と通知は workflow 側が down を見て行う)

set -uo pipefail

ATTEMPTS="${ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-20}"
TIMEOUT="${TIMEOUT:-15}"

# name | url | expected status | expected body substring
TARGETS=(
  'web|https://yuniruyuni.net/health|200|"status":"ok"'
  'costume|https://costume.yuniruyuni.net/health|200|"status":"ok"'
  'post|https://post.yuniruyuni.net/health|200|"status":"ok"'
  'tags|https://tags.yuniruyuni.net/health|200|"status":"ok"'
  'fighter|https://fighter.yuniruyuni.net/health|200|"status":"ok"'
  'template|https://template.yuniruyuni.net/health|200|"status":"ok"'
  # lom は /health を持たない静的 SPA なのでトップページを見る。
  'lom|https://lom.yuniruyuni.net/|200|<html'
  # n8n 本体は Access の後ろにあり、edge が 302 を返すだけで origin に届かない。
  # /webhook/* だけは Access を bypass しているので、登録されていない webhook を
  # 叩いて n8n 自身の 404 が返ることで生存を確かめる (落ちていれば 502 / 530)。
  'n8n|https://n8n.yuniruyuni.net/webhook/uptime-probe|404|is not registered'
)

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

probe() {
  local name="$1" url="$2" want_status="$3" want_body="$4"
  local attempt status detail body="$workdir/$name.body"
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    status="$(curl -sS -o "$body" -w '%{http_code}' --max-time "$TIMEOUT" \
      -A 'yuniruyuni.net-uptime/1 (+https://github.com/yuniruyuni/yuniruyuni.net)' \
      "$url" 2>"$workdir/$name.err")" || true
    if [[ "$status" == "$want_status" ]] && grep -qF -- "$want_body" "$body"; then
      printf 'up|%s|%s|%s|%s\n' "$name" "$url" "$status" "attempt $attempt" >"$workdir/$name.result"
      return
    fi
    if [[ "$status" == "000" ]]; then
      detail="$(head -c 200 "$workdir/$name.err" | tr '\n|' '  ')"
    elif [[ "$status" != "$want_status" ]]; then
      detail="expected $want_status"
    else
      detail="body lacks expected text"
    fi
    if ((attempt < ATTEMPTS)); then
      sleep "$RETRY_DELAY"
    fi
  done
  printf 'down|%s|%s|%s|%s\n' "$name" "$url" "$status" "$detail (after $ATTEMPTS attempts)" >"$workdir/$name.result"
}

for target in "${TARGETS[@]}"; do
  IFS='|' read -r name url want_status want_body <<<"$target"
  probe "$name" "$url" "$want_status" "$want_body" &
done
wait

down=()
report="| | Target | URL | Status | Detail |"$'\n'"|---|---|---|---|---|"$'\n'
for target in "${TARGETS[@]}"; do
  IFS='|' read -r name _ <<<"$target"
  IFS='|' read -r state rname url status detail <"$workdir/$name.result"
  if [[ "$state" == "up" ]]; then
    mark=":white_check_mark:"
  else
    mark=":x:"
    down+=("$rname")
  fi
  report+="| $mark | $rname | $url | $status | $detail |"$'\n'
done

printf '%s' "$report"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '## Uptime\n\n%s' "$report" >>"$GITHUB_STEP_SUMMARY"
fi

down_csv="$(IFS=,; printf '%s' "${down[*]}")"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'down=%s\n' "$down_csv"
    printf 'report<<__UPTIME_REPORT__\n%s__UPTIME_REPORT__\n' "$report"
  } >>"$GITHUB_OUTPUT"
fi

if ((${#down[@]} > 0)); then
  printf '\nDOWN: %s\n' "$down_csv" >&2
fi
