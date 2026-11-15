#!/bin/sh
# 初回起動時（データディレクトリが空のとき）だけ実行される。
# サービスごとにロールと論理DBを作り、共有 Postgres を分離して使う。
set -eu

create_database() {
    db="$1"
    role="$2"
    password="$3"

    psql -v ON_ERROR_STOP=1 \
        -v db="$db" -v role="$role" -v password="$password" \
        --username "$POSTGRES_USER" --dbname postgres <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db', :'role') \gexec
SQL
}

create_database homebox homebox "$HOMEBOX_DB_PASSWORD"
create_database memos memos "$MEMOS_DB_PASSWORD"
create_database vikunja vikunja "$VIKUNJA_DB_PASSWORD"
create_database wardrowbe wardrowbe "$WARDROWBE_DB_PASSWORD"
