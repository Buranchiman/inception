#!/bin/bash
set -e

# Read passwords from Docker secrets
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

# 1. Folders MariaDB needs
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

# 2. System tables (only if the data directory is empty)
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "Initializing data directory..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

# 3. Our database and users (only on first start)
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    echo "Creating database and users..."

    mariadbd --user=mysql --skip-networking &
    pid=$!

    for i in $(seq 1 30); do
        if mariadb-admin ping --silent; then
            break
        fi
        sleep 1
    done

    mariadb -u root <<EOF
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

    mariadb-admin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait "$pid"
    echo "Initialization done."
fi

# 4. Start MariaDB in the foreground as the container's main process
echo "Starting MariaDB..."
exec mariadbd --user=mysql
