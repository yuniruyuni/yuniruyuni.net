# PostgreSQL 18
#
# DB そのものを提供するだけ。どのアプリがどの DB を使うかは知らない。
#
# 2026-08-23 まで、ここにも dbApps というアプリ一覧があり、DB・ロール・
# 所有権・パスワードを作っていた。yunirun も同じものを作るので二重管理に
# なっており、しかも一覧が古くなっていた (template を挙げていたが、実際の
# DB 名は scaffold に変わっていた)。PostgreSQL が長く再起動していなかった
# ため表面化していなかっただけで、次の起動で消したはずの DB が復活する
# 状態だった。
#
# 今は yunirun だけが DB とロールを作る。アプリ側は yunirun.jsonc に
# database と databaseName を書き、yunirun がそれを収束させる。
#
# 権限の責務分担:
#   yunirun    : ロールの存在、パスワード、DB の所有権、
#                app ロールへの CONNECT と schema USAGE
#   pgschema   : table 等のオブジェクトと、app ロールへの per-table GRANT
#
# table 単位の権限は必ずアプリ側の schema ファイルで宣言する。pgschema は
# 宣言的なので、宣言されていない権限は「余分なもの」として REVOKE される。
# 外から GRANT ... ON ALL TABLES を撒くと、それが毎回 REVOKE されては
# 復活する振動になり、その間 app ロールが permission denied になる。
# 実際 template でこれが起きていた (2026-08-21 に解消)。
#
# 「宣言し忘れた table は権限が付かない」= deploy 時に気づける、という性質を
# 保つのが狙い。詳細は StreamTagInventory の ADR 0009 を参照。

{ pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;

    settings = {
      # ALTER ROLE のパスワードがログに出ないようにする。
      log_statement = "none";
    };

    # local の md5 行は VPS 上のコンテナ向け。コンテナは独立した netns に
    # 置いており、ホストの 127.0.0.1:5432 には到達できない。そこで
    # /run/postgresql の Unix ソケットを bind mount して繋ぐ
    # (services/yunirun.nix)。既定では postgres 以外は peer 認証になり
    # "Peer authentication failed" で弾かれるため、パスワード認証を許可する
    # 行を足す。
    #
    # 到達性は TCP の 127.0.0.1/32 md5 と同じ (ローカルからパスワードで接続)
    # で、権限が増えるわけではない。
    #
    # postgres だけが peer で入れる。yunirun はこの経路で DB を収束させる。
    authentication = ''
      # TYPE  DATABASE        USER            ADDRESS         METHOD
      local   all             postgres                        peer
      local   all             all                             md5
      host    all             all             127.0.0.1/32    md5
    '';
  };
}
