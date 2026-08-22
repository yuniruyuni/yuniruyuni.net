# yunirun — VPS 上でコンテナ化したアプリを動かすデプロイシステム。
#
# ここに書くのは「どのリポジトリを取り込むか」という取り込みの意思決定だけ。
# アプリの中身に関する設定 (ポート、環境変数、ワークロード) は各リポジトリの
# yunirun.jsonc にあり、デプロイ時に運ばれてくる。
#
# かつて services/apps.nix が同じ役目を担っていたが、こちらへ全て移し終えて
# 撤去した。ポート帯と uid 帯は並行運用のためにずらしたものをそのまま使う。

{ ... }:

{
  services.yunirun = {
    enable = true;
    domain = "yuniruyuni.net";

    # 生成した秘密を復号できる管理者の鍵。ホストを失ったときの復旧経路になる。
    # secrets/secrets.nix の onepassword と同じもの。
    adminRecipient = "age1t5u8r467lwp2t5d0qjr38va4nmly3wyg5k9fwttaakmu66q4zyvqq58qav";

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
    apps = {
      template = "yuniruyuni/template";
      costume = "yuniruyuni/costume";
      lom = "yuniruyuni/LegendOfManaWeapon";
      web = "yuniruyuni/web";
      tags = "yuniruyuni/StreamTagInventory";
      post = "yuniruyuni/StreamerPost";

      # fighter だけ認可先を明示する。
      #
      # このリポジトリは OIDC の sub claim prefix をカスタマイズしていて、
      # repo:<owner>/<repo> ではなく数値 id を含む形になっている。実測値:
      #   gh api repos/yuniruyuni/FighterNotes/actions/oidc/customization/sub
      #   -> "sub_claim_prefix": "repo:yuniruyuni@85034901/FighterNotes@1313852776"
      # リポジトリ名から導けないのでそのまま書く。
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
