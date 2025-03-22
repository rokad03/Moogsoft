#!/bin/bash

#	*******************************************************************************
#	*                       Copyright (c) Moogsoft Inc 2019                       *
#	*                                                                             *
#	*-----------------------------------------------------------------------------*
#	*                                                                             *
#	* All information contained herein is and remains the property of Moogsoft    *
#	* Inc. The intellectual and technical concepts contained herein may be        *
#	* covered by U.S. and Foreign Patents or patents in process, are protected by *
#	* trade secret law, and cannot be disseminated beyond authorized users.       *
#	*                                                                             *
#	* This source code is confidential and protected by copyright law. Any person *
#	* who believes that they are viewing it without permission is asked to notify *
#	* Moogsoft Inc.'s legal department at legal@moogsoft.com. Dissemination of    *
#	* this information in any form or by any means is strictly forbidden unless   *
#	* prior written permission is obtained from Moogsoft Inc. This source code    *
#	* may be modified for purposes of configuration or integration into Moogsoft  *
#	* Inc.'s authorized customer's computer systems in accordance with the terms  *
#	* of the customer's license.                                                  *
#	*                                                                             *
#	* If you are uncertain about the means in which you may modify this source    *
#	* code, contact your Moogsoft Inc. customer representative or Moogsoft Inc.'s *
#	* legal department at legal@moogsoft.com.                                     *
#	*                                                                             *
#	*******************************************************************************

# Run as a command for interactive inputs:
# bash <(curl -s -k https://<myspeedyuser>:<myspeedypassword>@speedy.moogsoft.com/repo/aiops/install_percona_nodes.sh)
#
# Example with command line options on primary node:
# bash <(curl -s -k https://<myspeedyuser>:<myspeedypassword>@speedy.moogsoft.com/repo/aiops/install_percona_nodes.sh) -d -i 10.101.10.109,10.101.10.110,10.101.10.112 -p
#
# Example with command line options on non-primary nodes:
# bash <(curl -s -k https://<myspeedyuser>:<myspeedypassword>@speedy.moogsoft.com/repo/aiops/install_percona_nodes.sh) -d -i 10.101.10.109,10.101.10.110,10.101.10.112
#
# Example with command line options for single node cluster:
# bash <(curl -s -k https://<myspeedyuser>:<myspeedypassword>@speedy.moogsoft.com/repo/aiops/install_percona_nodes.sh) -d -i 10.101.10.109
#
# Hostnames can also be used instead of IPs

SCRIPT_ARGS="$@"
ERMINTRUDE_PASSWORD="m00"
RAM_PERCENT=50
SINGLE_NODE=0
LOGFILE="./install_percona_nodes_$(date +%Y%m%d-%H%M%S).log"
PXC_VERSION="8.0.35"
PXB_VERSION="8.0.35"

#Default DB names
MOOGDB="moogdb"
MOOG_REFERENCE="moog_reference"
HISTORIC_MOOGDB="historic_moogdb"
MOOG_INTDB="moog_intdb"

f_show_help() {
	echo "Command line options:"
	echo
	echo "   -d|--db-only                  Set database to be the main application on this server,"
	echo "                                 allowing it to use up to 80% of the RAM (default is 50%)"
	echo
	echo "   -p|--primary                  Set this node as primary, so it starts with default bootstrap enabled"
	echo "   -i|--ips [IP1,IP2,IP3]        Comma separated list of the nodes IP addresses or hostnames"
	echo
	echo "   -n|--no-binlog-db-names [moogdb,moog_reference,historic_moogdb,moog_intdb]"
	echo "                                 Comma separated list of database names in the provided order"
	echo "                                 The binlog will be disabled for these databases"
	echo
	echo "   -m|--moogsoft-password        The password used by the user ermintrude"
	echo
	echo "   -h|--help                     Displays this help information"
	echo
}

f_log() {
	echo -e "$1"
	echo -e "[$(date +%Y%m%d\ %H:%M:%S)]: $1" >> $LOGFILE
}

f_invalid() {
	f_log "Invalid value: $1"
	f_show_help
	exit 1
}

f_exit() {
	echo -e "Error: $1\nAborting installation...\n\nFor more information check the logfile $LOGFILE"
	exit 1
}

f_log "Percona Cluster Installer"
f_log

[ "$SCRIPT_ARGS" ] && {
	args=$(getopt -u -o phdm:n:i: -l help,primary,db-only,no-binlog-db-names:,ips:,moogsoft-password: -- $SCRIPT_ARGS)
	# Exit if getopt returns non-zero
	if [[ $? != 0 ]]; then
		exit 1
	fi
	eval set -- "$args"
	while true; do
		case "$1" in
			-h|--help)
				f_show_help
				exit 2
				;;
			-d|--db-only)
				RAM_PERCENT=80
				shift
				;;
			-p|--primary)
				PRIMARY=y
				shift
				;;
			-i|--ips)
				IP1=$(echo "$2" | awk -F, '{print $1}')
				IP2=$(echo "$2" | awk -F, '{print $2}')
				IP3=$(echo "$2" | awk -F, '{print $3}')
				shift 2
				;;
			-n|--no-binlog-db-names)
				[ ! -z $(echo "$2" | awk -F, '{print $1}') ] && MOOGDB=$(echo "$2" | awk -F, '{print $1}')
				[ ! -z $(echo "$2" | awk -F, '{print $2}') ] && MOOG_REFERENCE=$(echo "$2" | awk -F, '{print $2}')
				[ ! -z $(echo "$2" | awk -F, '{print $3}') ] && HISTORIC_MOOGDB=$(echo "$2" | awk -F, '{print $3}')
				[ ! -z $(echo "$2" | awk -F, '{print $4}') ] && MOOG_INTDB=$(echo "$2" | awk -F, '{print $4}')
				shift 2
				;;
			-m|--moogsoft-password)
				[ ! -z "$2" ] && {
					ERMINTRUDE_PASSWORD="$2";
					shift 2;
				} || shift
				;;
			--)
				shift; break ;;
			*)
				f_invalid
				exit 2
				;;
		esac
	done
} || {
	PRIMARY=""
	while [[ "$PRIMARY" == "" ]];
	do
		read -p "Setup this node as Primary node [y/N]: " PRIMARY
		case "${PRIMARY}" in
			[Yy]* ) PRIMARY="y";;
			[Nn]* ) PRIMARY="n";;
			"" ) PRIMARY="n";;
			* ) PRIMARY=""; echo;;
		esac
	done

	echo
	
	DBONLY=""
	while [[ "$DBONLY" == "" ]];
	do
		read -p "If this is a database only server you can allow Percona node to use up to 80% of the RAM [y/N]: " DBONLY
		case "${DBONLY}" in
			[Yy]* ) DBONLY="y";;
			[Nn]* ) DBONLY="n";;
			"" ) DBONLY="n";;
			* ) DBONLY=""; echo;;
		esac
	done
	
	echo
	
	if [[ "$DBONLY" =~ ^[Yy]$ ]];
	then
		RAM_PERCENT=80
	fi
		
	IP1=""
	while [[ "$IP1" == "" ]];
	do
		read -p "Enter IP of Node #1: " IP1
		case "${IP1}" in
			"" ) echo;;
			* ) break;;
		esac
	done
	read -p "Enter IP of Node #2 (Not needed for single node installations): " IP2
	read -p "Enter IP of Node #3 (Not needed for single node installations): " IP3
}

if [[ -z "$IP1" ]];
then
	f_invalid "for IP1"
elif [[ ! -z "$IP1" ]] && ( ( [[ ! -z "$IP2" ]] && [[ -z "$IP3" ]] ) || ( [[ -z "$IP2" ]] && [[ ! -z "$IP3" ]] ) );
then
	f_invalid "missing second or third IP"
elif [[ -z "$IP2" ]] && [[ -z "$IP3" ]];
then
	SINGLE_NODE=1;
	PRIMARY="y";
fi

f_log "Disabling SELinux"
setenforce 0
if [ -z "$(grep vm.swappiness /etc/sysctl.conf)" ]; then
	f_log "Setting less aggressive RAM contents copy to SWAP"
	echo 'vm.swappiness=1' >> /etc/sysctl.conf;
	sysctl -p &>> $LOGFILE
	test $? -ne 0 && f_exit "sysctl could not reload"
fi

# Install Percona only if it is not already installed
if [[ -z $(rpm -qa|grep -i percona-xtradb-cluster-server) ]];
then
	if [ -z $(rpm -qa|grep percona-release) ]; then
		f_log "Installing Percona repository"
		yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm &>> $LOGFILE
		test $? -ne 0 && f_exit "Percona repository could not be installed"
	else
		f_log "Updating Percona repository (if update available)"
		yum -y update percona-release &>> $LOGFILE
	fi

	f_log "Configuring percona-release for PXC80"
	percona-release setup -y pxc80 &>> $LOGFILE

	f_log "Installing Percona XtraDB Cluster ${PXC_VERSION} and XtraBackup ${PXB_VERSION}"
	yum -y install percona-xtradb-cluster-server-${PXC_VERSION} percona-xtrabackup-80-${PXB_VERSION} &>> $LOGFILE
	test $? -ne 0 && f_exit "Percona XtraDB Cluster could not be installed"
else
	INSTALLED_VERSION=$(rpm -qa --qf "%{NAME}==%{VERSION}\n" | grep -i percona-xtradb-cluster-server | awk -F== '{print $2}')
	if [[ "${INSTALLED_VERSION}" != "${PXC_VERSION}" ]];
	then
		f_exit "Installed Percona version ${INSTALLED_VERSION} does not match the expected version"
	fi
fi

[ -z $(rpm -qa|grep -i xinetd) ] && {
	f_log "Installing xinetd"
	yum -y install xinetd &>> $LOGFILE
	test $? -ne 0 && f_exit "xinetd could not be installed"
}

f_log "Creating the DB configuration"

IDB_BUF_POOL_SIZE_IN_MB=$(($(free -m|head -n -1|tail -n -1|awk '{print $2}')*$RAM_PERCENT/100)) # % of the RAM in megabytes
CORES_NUM=$(cat /proc/cpuinfo | grep ^processor|wc -l)
IDB_LOG_FILE_SIZE_IN_MB=$(((IDB_BUF_POOL_SIZE_IN_MB*2/100>1024)) && echo $((IDB_BUF_POOL_SIZE_IN_MB*2/100)) || echo 1024)
IDB_BUF_POOL_INST=$(((IDB_BUF_POOL_SIZE_IN_MB>=16384)) && echo $((IDB_BUF_POOL_SIZE_IN_MB/8192)) || echo 8)
WS_APPLIER_THREADS=$(((CORES_NUM<32)) && echo 8 || echo $((CORES_NUM/4)))

f_log "The following settings are based on detected hardware:"
f_log "innodb-log-file-size           = ${IDB_LOG_FILE_SIZE_IN_MB}M"
f_log "innodb-buffer-pool-size        = ${IDB_BUF_POOL_SIZE_IN_MB}M"
f_log "innodb_buffer_pool_instances   = ${IDB_BUF_POOL_INST}"
f_log "wsrep_applier_threads          = ${WS_APPLIER_THREADS}"

cat > /etc/my.cnf << _EOF_
[mysqld]
# GENERAL #
basedir                        = /usr/
user                           = mysql
default-storage-engine         = InnoDB
socket                         = /var/run/mysqld/mysqld.sock
pid-file                       = /var/run/mysqld/mysqld.pid
port                           = 3306
log_bin_trust_function_creators = 1
thread_stack                   = 524288

character-set-server           = utf8mb3
collation-server               = utf8mb3_general_ci

# MyISAM #
key-buffer-size                = 32M
myisam-recover-options         = FORCE,BACKUP

# SAFETY #
max-allowed-packet             = 128M
max-connect-errors             = 1000000

# DATA STORAGE #
datadir                        = /var/lib/mysql/

# CACHES AND LIMITS #
tmp-table-size                 = 32M
max-heap-table-size            = 32M
max-connections                = 500
thread-cache-size              = 128
open-files-limit               = 65535
table-definition-cache         = 1024
table-open-cache               = 8000
max_prepared_stmt_count        = 1048576
group_concat_max_len           = 1048576

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = ${IDB_LOG_FILE_SIZE_IN_MB}M
innodb-flush-log-at-trx-commit = 2
innodb-file-per-table          = 1
innodb-buffer-pool-size        = ${IDB_BUF_POOL_SIZE_IN_MB}M
innodb_buffer_pool_instances   = ${IDB_BUF_POOL_INST}
innodb_autoinc_lock_mode       = 2

# LOGGING #
log-timestamps                 = SYSTEM
log-error                      = /var/log/mysqld.log
log-queries-not-using-indexes  = 0
slow-query-log-file            = /var/log/mysql-slow.log
slow-query-log                 = 0
log_error_suppression_list     = 'MY-013360'

# REPLICATION #
disable-log-bin
# Uncomment the following only for single node cluster
# binlog-ignore-db=${MOOGDB}
# binlog-ignore-db=${MOOG_REFERENCE}
# binlog-ignore-db=${HISTORIC_MOOGDB}
# binlog-ignore-db=${MOOG_INTDB}
binlog_format                  = ROW
sync_binlog                    = 0

# PERF #
performance_schema             = ON

# Moogsoft MySQL 5.6 optimizations
default_tmp_storage_engine     = MyISAM

# wsrep settings
wsrep_provider                 = /usr/lib64/galera4/libgalera_smm.so
wsrep_cluster_address          = gcomm://
wsrep_log_conflicts
wsrep_cluster_name             = pxc-cluster
wsrep_node_name                = pxc-node-$(hostname)
pxc_strict_mode                = ENFORCING
wsrep_sst_method               = xtrabackup-v2
wsrep_applier_threads          = ${WS_APPLIER_THREADS}
wsrep_sync_wait                = 0
wsrep_provider_options         = "gcache.size=4G"
wsrep_retry_autocommit         = 10

# Authentication and SSL #
default_authentication_plugin  = mysql_native_password
pxc-encrypt-cluster-traffic    = OFF 

[mysqldump]
quick
quote-names
max_allowed_packet             = 16M

[client]
default-character-set=utf8mb3
port                           = 3306
socket                         = /var/run/mysqld/mysqld.sock

[mysqld_safe]
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
socket                         = /var/run/mysqld/mysqld.sock
nice                           = 0

[mysql]

[isamchk]

_EOF_

touch /var/log/mysql-error.log
touch /var/log/mysql-slow.log
chown mysql /var/log/mysql-*.log

f_log "Setting cluster checker on port 9198"
cat > /etc/xinetd.d/mysqlchk << _EOF_
# default: on
# description: mysqlchk
service mysqlchk
{
disable = no
flags = REUSE
socket_type = stream
port = 9198
wait = no
user = nobody
server = /usr/bin/clustercheck
log_on_failure += USERID
only_from = 0.0.0.0/0
per_source = UNLIMITED
}
_EOF_

[ -z "$(grep "9198/tcp" /etc/services)" ] && \
	echo "mysqlchk        9198/tcp                # mysqlchk" >> /etc/services

f_log "Starting xinetd"
systemctl restart xinetd &>> $LOGFILE
test $? -ne 0 && f_exit "xinetd was not able to start"

if [[ "$PRIMARY" =~ ^[Yy]$ ]];
then
	pkill -9 mysqld; pkill -9 mysqld_safe
	sleep 10
	rm -rf /var/lib/mysql/*
	mysqld --initialize-insecure --user=mysql &>> $LOGFILE
	test $? -ne 0 && f_exit "mysqld was not able to initialize"

	f_log "Starting Percona in bootstrap mode"
	systemctl start mysql &>> $LOGFILE
	test $? -ne 0 && f_exit "mysqld was not able to start"

	f_log "Waiting for Percona to start"
	timeout 30 bash -c 'until [[ $(OUTPUT=$(mysql -u root -e "select version();" 2>/dev/null); echo $?) == 0 ]]; do sleep 0.5; done';
	test $? -ne 0 && f_exit "mysqld was not able to start in time"

	f_log "Setting this node as primary"

	f_log "Adding clustercheckuser@localhost to the DB and granting required rights"
	mysql -u root -e "CREATE USER IF NOT EXISTS 'clustercheckuser'@'localhost' IDENTIFIED BY 'clustercheckpassword\!';" &>> $LOGFILE
	test $? -ne 0 && f_exit "clustercheck@localhost user could not be added"
	mysql -u root -e "GRANT PROCESS ON *.* TO 'clustercheckuser'@'localhost';" &>> $LOGFILE
	test $? -ne 0 && f_exit "Could not grant PROCESS rights to clustercheckuser@localhost"

	f_log "Adding ermintrude@% user to the DB for Moogsoft"
	mysql -u root -e "CREATE USER IF NOT EXISTS 'ermintrude'@'%' IDENTIFIED BY '$ERMINTRUDE_PASSWORD';" &>> $LOGFILE
	test $? -ne 0 && f_exit "ermintrude@% user could not be added"

	f_log "Adding ermintrude@localhost user to the DB for Moogsoft"
        mysql -u root -e "CREATE USER IF NOT EXISTS 'ermintrude'@'localhost' IDENTIFIED BY '$ERMINTRUDE_PASSWORD';" &>> $LOGFILE
        test $? -ne 0 && f_exit "ermintrude@localhost user could not be added"

	f_log "Granting all privileges on *.* to ermintrude users"
	mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'ermintrude'@'%', 'ermintrude'@'localhost';" &>> $LOGFILE
	test $? -ne 0 && f_exit "Privileges could not be granted"

	f_log "Granting process on *.* to ermintrude users"
	mysql -u root -e "GRANT PROCESS ON *.* TO 'ermintrude'@'%', 'ermintrude'@'localhost';" &>> $LOGFILE
	test $? -ne 0 && f_exit "Privileges could not be granted"

	f_log "Flushing mysql user privileges"
	mysql -u root -e "FLUSH PRIVILEGES;" &>> $LOGFILE
	test $? -ne 0 && f_exit "could not flush mysql user privileges"

	[ $SINGLE_NODE -eq 0 ] && \
		sed -i "s/.*wsrep_cluster_address.*=.*gcomm:\/\/.*/wsrep_cluster_address=gcomm:\/\/$IP1,$IP2,$IP3/g" \
			/etc/my.cnf || \
		f_log "This is a single node Percona installation. This node will start in bootstrap mode unless the setting wsrep_cluster_address in /etc/my.cnf is set with all IPs of the nodes. Single node can also get performance benefit when binlog-ignore-db options are uncommented in /etc/my.cnf. These options should remain commented for multi-node cluster."
else
	f_log "Setting this node to join the cluster"
	sed -i "s/.*wsrep_cluster_address.*=.*gcomm:\/\/.*/wsrep_cluster_address=gcomm:\/\/$IP1,$IP2,$IP3/g" /etc/my.cnf

	f_log "Starting Percona in normal (non-bootstrap) mode"
	systemctl start mysql &>> $LOGFILE
	test $? -ne 0 && f_exit "mysqld was not able to start"
fi

if [[ $(mount | egrep '^proc' | grep "hidepid=2") != "" ]];
then
	echo "WARNING: System is using hidepid=2 on the procfs mount, and Percona may not run/perform SST correctly with this configuration, unless the mount has also been defined with a unix group id which the Percona unix user is also a member of. For example: [proc /proc proc defaults,hidepid=2,gid=1001 0 0], where '1001' is the unix group id. This can be configured in /etc/fstab"
fi

f_log "Done"
f_log
