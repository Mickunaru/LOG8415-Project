#!/bin/bash

set -e
exec > /var/log/setup_worker.log 2>&1

MYSQL_ROOT_PWD="${MYSQL_ROOT_PWD}"
MYSQL_REPLICA_PWD="${MYSQL_REPLICA_PWD}"
MYSQL_PROXY_PWD="${MYSQL_PROXY_PWD}"
SOURCE_IP="${SOURCE_IP}"
SERVER_ID="${SERVER_ID}"

if [ "$SERVER_ID" -le 1 ]; then
  echo "SERVER_ID should be greater than 1 for worker nodes"
  exit 1
fi

apt-get update
apt-get install -y mysql-server wget unzip python3 python3-pip sysbench

until mysqladmin ping -h "$SOURCE_IP" -u "replica_user" -p"$MYSQL_REPLICA_PWD" --silent; do
  echo "Manager MySQL not ready"
  sleep 3
done

while true; do
  MASTER_STATUS=$(mysql -h "$SOURCE_IP" -u "replica_user" -p"$MYSQL_REPLICA_PWD" -N -B -e "SHOW MASTER STATUS;" 2>/dev/null || true)

  if [[ -n "$MASTER_STATUS" ]]; then
    echo "Got master status: $MASTER_STATUS"
    break
  fi

  echo "Waiting for manager master status"
  sleep 2
done

MASTER_LOG_FILE=$(echo "$MASTER_STATUS" | awk '{print $1}')
MASTER_LOG_POS=$(echo "$MASTER_STATUS" | awk '{print $2}')

MYSQL_CONFIG=/etc/mysql/mysql.conf.d/mysqld.cnf
PRIVATE_IP=$(hostname -I | awk '{print $1}')

sed -i "s/^bind-address\s*=.*/bind-address = $PRIVATE_IP/" $MYSQL_CONFIG
sed -i "s/^#\s*server-id\s*=.*/server-id = $SERVER_ID/" $MYSQL_CONFIG
sed -i "s/^#\s*log_bin/log_bin/" $MYSQL_CONFIG
sed -i "s/^#\s*binlog_do_db\s*=.*/binlog_do_db = sakila/" $MYSQL_CONFIG
echo "relay-log = /var/log/mysql/mysql-relay-bin.log" >> $MYSQL_CONFIG

systemctl restart mysql

until mysqladmin ping -u root -p"${MYSQL_ROOT_PWD}" --silent; do
  echo "Waiting for local MySQL"
  sleep 2
done

cd /tmp
wget -q https://downloads.mysql.com/docs/sakila-db.zip
unzip -o sakila-db.zip

mysql -u root -p"${MYSQL_ROOT_PWD}" -e "CREATE DATABASE IF NOT EXISTS sakila;"
mysql -u root -p"${MYSQL_ROOT_PWD}" -e "FLUSH TABLES WITH READ LOCK;"
mysql -u root -p"${MYSQL_ROOT_PWD}" sakila < sakila-db/sakila-schema.sql
mysql -u root -p"${MYSQL_ROOT_PWD}" sakila < sakila-db/sakila-data.sql
mysql -u root -p"${MYSQL_ROOT_PWD}" -e "UNLOCK TABLES;"

mysql <<MYSQL_EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PWD}';

CREATE USER 'proxy_user'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PROXY_PWD}';
GRANT SELECT, SHOW VIEW ON sakila.* TO 'proxy_user'@'%';

FLUSH PRIVILEGES;

CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${SOURCE_IP}',
  SOURCE_USER='replica_user',
  SOURCE_PASSWORD='${MYSQL_REPLICA_PWD}',
  SOURCE_LOG_FILE='$${MASTER_LOG_FILE}',
  SOURCE_LOG_POS=$${MASTER_LOG_POS};

START REPLICA;
MYSQL_EOF

mysql -u root -p"${MYSQL_ROOT_PWD}" -e "SET GLOBAL read_only = ON;"

echo "read_only = 1" >> /etc/mysql/mysql.conf.d/replica.cnf

systemctl restart mysql

sysbench /usr/share/sysbench/oltp_read_only.lua --mysql-db=sakila --mysql-user="root" --mysql-password="${MYSQL_ROOT_PWD}" prepare
sysbench /usr/share/sysbench/oltp_read_only.lua --mysql-db=sakila --mysql-user="root" --mysql-password="${MYSQL_ROOT_PWD}" run | tee /var/log/sysbench_results.log

echo READY > /var/run/ready