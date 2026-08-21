# yunirun — VPS 上でコンテナ化したアプリを動かすデプロイシステム。
#
# ここに書くのは「どのリポジトリを取り込むか」という取り込みの意思決定だけ。
# アプリの中身に関する設定 (ポート、環境変数、ワークロード) は各リポジトリの
# yunirun.jsonc にあり、デプロイ時に運ばれてくる。
#
# 現行の services/apps.nix とは別のポート帯・uid 帯を使うので並行して動く。
# 移行が済んだら apps.nix ごと削除する。

{ ... }:

{
  services.yunirun = {
    enable = true;
    domain = "yuniruyuni.net";

    # 生成した秘密を復号できる管理者の鍵。ホストを失ったときの復旧経路になる。
    # secrets/secrets.nix の onepassword と同じもの。
    adminRecipient = "age1t5u8r467lwp2t5d0qjr38va4nmly3wyg5k9fwttaakmu66q4zyvqq58qav";

    # 現行の services/apps.nix と帯を重ねない。移行が済んだら既定値に戻す。
    basePort = 8200;
    baseUID = 6000;

    # 取り込むアプリ。この一覧がそのまま opkssh の認可になるので、
    # アプリ側が自分を勝手に取り込ませることはできない。
    #
    # まずは template だけで実証する。アプリ名を template のままにすると
    # 現行の apps.nix 側と DB (template) や unit 名を共有してしまうので、
    # 検証中は別名にする。切り替え時に template へ改名する。
    apps = {
      template2 = "yuniruyuni/template";

      # DB を持たない 3 つ。旧 apps.nix 側と並行して立ち上げ、動作を確認してから
      # ingress を切り替える。名前に 2 を付けているのは、旧側と DB や unit 名を
      # 共有しないため (この 3 つは DB を持たないが、unit 名は衝突する)。
      costume2 = "yuniruyuni/costume";
      lom2 = "yuniruyuni/LegendOfManaWeapon";
      web2 = "yuniruyuni/web";

      # DB と秘密を持つ 2 つ。既存の DB とパスワードをそのまま引き継ぐので、
      # 旧 apps.nix 側と並行して動かしても認証は壊れない (アプリ側の
      # yunirun.jsonc で databaseName と databasePasswords を指定している)。
      tags2 = "yuniruyuni/StreamTagInventory";
      post2 = "yuniruyuni/StreamerPost";
    };
  };
}
