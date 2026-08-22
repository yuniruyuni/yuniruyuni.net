# fighter の DB トンネル用サービストークンとポリシー。撤去の途中段階。
#
# 本体は既に消したが、この 2 つだけは一度に消せない。db の Access アプリが
# ポリシーを参照しており、Cloudflare はアプリから使われているポリシーの削除を
# 409 で拒む。そして Terraform は「アプリの更新」より先に「ポリシーの削除」を
# 実行するため、同じ apply の中では順番を作れなかった。
#
# そこで 2 段階に分ける。この apply ではポリシーを残したままアプリ側の参照を
# 外し、次の apply でこのファイルごと消す。
#
# fighter は VPS へ移り DB へは Unix ソケットで繋ぐので、このトークンは既に
# 誰も使っていない。
locals {
  fighter_db_workloads = toset(["runtime", "migration", "cleanup"])
}

resource "cloudflare_zero_trust_access_service_token" "fighter_db" {
  for_each = local.fighter_db_workloads

  account_id = var.cloudflare_account_id
  name       = "Fighter Notes ${title(each.value)} DB Access"
}

resource "cloudflare_zero_trust_access_policy" "fighter_db" {
  account_id = var.cloudflare_account_id
  name       = "Fighter Notes DB Service Tokens"
  decision   = "non_identity"

  include = [for token in cloudflare_zero_trust_access_service_token.fighter_db : {
    service_token = {
      token_id = token.id
    }
  }]
}
