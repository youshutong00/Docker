#!/bin/bash
/usr/sbin/sshd &

VOLUME_HOME="/var/lib/mysql"
CONF_FILE="/etc/my.cnf"

StartMySQL(){
	/etc/init.d/mysqld start
	mysql -uroot -e "status;"
	if [ $? -ne 0 ]; then
		echo 'Start MySQL Error...'
		exit 5
	fi
}

CreateUser(){
	echo "Start MySQL"
	StartMySQL
	if [ "$MYSQL_PASS" == "**Random**" ]; then
		unset MYSQL_PASS
	fi
	PASS=${MYSQL_PASS:-$(pwgen -s 12 1)}
	_word=$( [ $MYSQL_PASS ] && echo "Preset" || echo "Random" )
	echo "=> Creating MySQL user ${MYSQL_USER} with ${_word} password"
	mysql -uroot -e "CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '$PASS'"
	mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION"
	echo "=> Done !"
	echo "========================================================================"
	echo "You can now connect to this MySQL Server using:"
	echo "========================================================================"
	echo "    mysql -u$MYSQL_USER -p$PASS -h<host> -P<port>"
	echo "Please remember to change the above password as soon as possible!"
	echo "MySQL user 'root' has no password but only allows local connections"
	echo "========================================================================"
	mysqladmin -uroot shutdown
}

if [ ! -d $VOLUME_HOME/mysql ]; then
	echo "=> An empty or uninitialized MySQL volume is detected in $VOLUME_HOME"
	echo "=> Installing MySQL ..."
	mysql_install_db &>/dev/null
	echo "=> Done!"
	echo "=> Creating admin user ..."
	CreateUser
else
	echo "=> Using an existing volume of MySQL"
fi


########MySQL Replication#####################
if [ ${REPLICATION_MASTER} == "**False**" ]; then
	unset REPLICATION_MASTER
fi
if [ ${REPLICATION_SLAVE} == "**False**" ]; then
	unset REPLICATION_SLAVE
fi

# Set MySQL REPLICATION - MASTER
if [ -n "${REPLICATION_MASTER}" ]; then 
	echo "=> Configuring MySQL replication as master ..."
	if [ ! -f /replication_configured ]; then
		RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"
		echo "=> Writting configuration file '${CONF_FILE}' with server-id=${RAND}"
		sed -i "s/^#server-id.*/server-id = ${RAND}/" ${CONF_FILE}
		sed -i "s/^#log-bin.*/log-bin = mysql-bin/" ${CONF_FILE}
		echo "=> Starting MySQL ..."
		StartMySQL
		echo "=> Creating a log user ${REPLICATION_USER}:${REPLICATION_PASS}"
		mysql -uroot -e "CREATE USER '${REPLICATION_USER}'@'%' IDENTIFIED BY '${REPLICATION_PASS}'"
		mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* TO '${REPLICATION_USER}'@'%'"
		echo "=> Done!"
		mysqladmin -uroot shutdown
		touch /replication_configured
	else
		echo "=> MySQL replication master already configured, skip"
	fi
fi

# Set MySQL REPLICATION - SLAVE
if [ -n "${REPLICATION_SLAVE}" ]; then 
	echo "=> Configuring MySQL replication as slave ..."
	if [ -n "${MYSQL_PORT_3306_TCP_ADDR}" ] && [ -n "${MYSQL_PORT_3306_TCP_PORT}" ]; then
		if [ ! -f /replication_configured ]; then
			RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"
			echo "=> Writting configuration file '${CONF_FILE}' with server-id=${RAND}"
			sed -i "s/^#server-id.*/server-id = ${RAND}/" ${CONF_FILE}
			sed -i "s/^#log-bin.*/log-bin = mysql-bin/" ${CONF_FILE}
			echo "=> Starting MySQL ..."
			StartMySQL
			echo "=> Setting master connection info on slave"
			mysql -uroot -e "CHANGE MASTER TO \
				MASTER_HOST='${MYSQL_PORT_3306_TCP_ADDR}',\
				MASTER_USER='${MYSQL_ENV_REPLICATION_USER}',\
				MASTER_PASSWORD='${MYSQL_ENV_REPLICATION_PASS}',\
				MASTER_PORT=${MYSQL_PORT_3306_TCP_PORT}, \
				MASTER_CONNECT_RETRY=30"
			echo "=> Done!"
			mysqladmin -uroot shutdown
			touch /replication_configured
		else
			echo "=> MySQL replicaiton slave already configured, skip"
		fi
	else 
		echo "=> Cannot configure slave, please link it to another MySQL container with alias as 'mysql'"
		exit 1
	fi
fi

exec mysqld_safe

