# yunirun — VPS 上でコンテナ化したアプリを動かすデプロイシステム。
#
# ここに書くのは「どのリポジトリを取り込むか」という取り込みの意思決定だけ。
# アプリの中身に関する設定 (ポート、環境変数、ワークロード) は各リポジトリの
# yunirun.jsonc にあり、デプロイ時に運ばれてくる。
#
# かつて services/apps.nix が同じ役目を担っていたが、こちらへ全て移し終えて
# 撤去した。ポート帯と uid 帯は並行運用のためにずらしたものをそのまま使う。

{ config, ... }:

{
  services.yunirun = {
    enable = true;
    domain = "yuniruyuni.net";

    # 生成した秘密を復号できる管理者の鍵。ホストを失ったときの復旧経路になる。
    # secrets/secrets.nix の onepassword と同じもの。
    adminRecipient = "age1t5u8r467lwp2t5d0qjr38va4nmly3wyg5k9fwttaakmu66q4zyvqq58qav";

    # 計測基盤 (メトリクス・ログ・可視化)。
    #
    # 外から HTTP を叩いても健全性の確認にはならない。Cloudflare の
    # stale-while-revalidate により、オリジンが完全に止まっていても 200 が
    # 返る (実測で確認済み)。オリジンの生死はここで見る。
    #
    # すべて 127.0.0.1 にだけ bind する。見るときは ssh のポート転送を使う:
    #   ssh -N -L 8090:127.0.0.1:8090 yuniruyuni.net
    observability.enable = true;

    # アラートの送り先。n8n の webhook に寄せる。
    #
    # その先 (Discord なのかメールなのか) は n8n 側で組む。通知先を変えるのに
    # yunirun も NixOS の宣言も触らずに済む。
    observability.alertWebhook = "http://127.0.0.1:5678/webhook/yunirun-alert";

    # アプリ側の秘密 (secrets/<ENV_NAME>.age) を復号する鍵。
    # 公開鍵は age1uar0qhs2aev0s56rh6ckp6exrt76xk7revwpqfgtkwhgu9w4nu5q9eekgs で、
    # yunirun recipient でも表示できる。
    secretsKeyPath = config.age.secrets.yunirun-secrets-key.path;

    # 割り当ての帯。旧 apps.nix と並行して動かすためにずらしたもの。
    # apps.nix は撤去したが、既定値に戻すと稼働中のアプリの uid とポートが
    # 動き、Cloudflare の ingress が指す先を失うのでこのまま使う。
    basePort = 8200;
    baseUID = 6000;

    # 取り込むアプリ。この一覧がそのまま opkssh の認可になるので、
    # アプリ側が自分を勝手に取り込ませることはできない。
    #
    # 名前の末尾に付けていた 2 は、旧 apps.nix と並行して動かす間だけの措置
    # だった。apps.nix を撤去したので外す。
    #
    # 名前は Linux ユーザ・unit 名・HAProxy の backend・opkssh の認可先に
    # そのまま出る。converge は宣言に無いものを片付けないため、ここを
    # 書き換えるだけでは旧名の資源が残り、しかも旧ユーザが uid とポートを
    # 握ったままで新しいユーザを作れない。この変更を入れる前に、ホスト上で
    # yunirun rename を 6 件走らせて割り当てを引き継がせてある。
    # principal は必須。yunirun 側に導出は無い。
    #
    # GitHub は 2026-07-15 以降に作られたリポジトリの sub を、名前ではなく
    # 数値 id を含む形にした。旧形式は名前空間の再利用に弱く、リポジトリを
    # 消して同じ名前で作り直せば同じ sub が再現する。OIDC の仕様は sub を
    # 二度と再割り当てされないものとしているので、旧形式はそれを満たさない。
    # 8 つとも opt-in して新形式へ揃えた。
    #
    # id は不変なので、リポジトリ名を変えてもここを直す必要はない。実測方法:
    #   gh api repos/<owner>/<repo>/actions/oidc/customization/sub
    apps = {
      template = {
        repo = "yuniruyuni/template";
        principal = "repo:yuniruyuni@85034901/template@1203258260:ref:refs/heads/main";
      };
      costume = {
        repo = "yuniruyuni/costume";
        principal = "repo:yuniruyuni@85034901/costume@1181870108:ref:refs/heads/main";
      };
      lom = {
        repo = "yuniruyuni/LegendOfManaWeapon";
        principal = "repo:yuniruyuni@85034901/LegendOfManaWeapon@1181342776:ref:refs/heads/main";
      };
      web = {
        repo = "yuniruyuni/web";
        principal = "repo:yuniruyuni@85034901/web@830180787:ref:refs/heads/main";
      };
      tags = {
        repo = "yuniruyuni/StreamTagInventory";
        principal = "repo:yuniruyuni@85034901/StreamTagInventory@836372101:ref:refs/heads/main";
      };
      post = {
        repo = "yuniruyuni/StreamerPost";
        principal = "repo:yuniruyuni@85034901/StreamerPost@1020573506:ref:refs/heads/main";
      };

      # fighter は 2026-07-27 作成で、最初から新形式だった。他の 6 つは
      # 後から opt-in して揃えたもの。
      #
      # 後半が :ref:refs/heads/main なのは、deploy job に environment: を
      # 付けていないため。付けると :environment:<name> に変わる。
      fighter = {
        repo = "yuniruyuni/FighterNotes";
        principal = "repo:yuniruyuni@85034901/FighterNotes@1313852776:ref:refs/heads/main";
      };
    };
  };
}
