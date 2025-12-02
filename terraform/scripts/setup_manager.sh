#!/bin/bash

set -e
exec > /var/log/setup_manager.log 2>&1

MYSQL_ROOT_PWD="${MYSQL_ROOT_PWD}"
MYSQL_REPLICA_PWD="${MYSQL_REPLICA_PWD}"

apt-get update
apt-get install -y mysql-server wget unzip python3 python3-pip

MYSQL_CONFIG="/etc/mysql/mysql.conf.d/mysqld.cnf"
PRIVATE_IP=$(hostname -I | awk '{print $1}')

sed -i "s/^bind-address\s*=.*/bind-address = $PRIVATE_IP/" $MYSQL_CONFIG
sed -i "s/^#\s*server-id/server-id/" $MYSQL_CONFIG
sed -i "s/^#\s*log_bin/log_bin/" $MYSQL_CONFIG
sed -i "s/^#\s*binlog_do_db\s*=.*/binlog_do_db = sakila/" $MYSQL_CONFIG

systemctl restart mysql

mysql <<MYSQL_EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PWD}';
FLUSH PRIVILEGES;

CREATE DATABASE IF NOT EXISTS sakila;
MYSQL_EOF

cd /tmp
wget https://downloads.mysql.com/docs/sakila-db.zip
unzip -o sakila-db.zip
if [ -f sakila-db/sakila-schema.sql ]; then
  mysql -u root -p"${MYSQL_ROOT_PWD}" -e "FLUSH TABLES WITH READ LOCK;"
  mysql -u root -p"${MYSQL_ROOT_PWD}" sakila < sakila-db/sakila-schema.sql
  mysql -u root -p"${MYSQL_ROOT_PWD}" sakila < sakila-db/sakila-data.sql
  mysql -u root -p"${MYSQL_ROOT_PWD}" -e "UNLOCK TABLES;"
fi

mysql -u root -p"${MYSQL_ROOT_PWD}" <<EOF
CREATE USER IF NOT EXISTS 'replica_user'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_REPLICA_PWD}';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replica_user'@'%';
FLUSH PRIVILEGES;
EOF

echo READY > /var/run/ready
