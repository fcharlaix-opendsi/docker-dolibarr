#!/bin/sh

# usage: get_env_value VAR [DEFAULT]
#    ie: get_env_value 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
get_env_value() {
	varName="${1}"
  varValue="$(eval echo "\$$varName")"
	fileVarName="${varName}_FILE"
  fileVarValue="$(eval echo "\$$fileVarName")"
	defaultValue="${2:-}"

	if [ "${varValue:-}" ] && [ "${fileVarValue:-}" ]; then
		echo >&2 "error: both ${varName} and ${fileVarName} are set (but are exclusive)"
		exit 1
	fi

	value="${defaultValue}"
	if [ "${varValue:-}" ]; then
	  value="${varValue}"
	elif [ "${fileVarValue:-}" ]; then
		value="$(cat "${fileVarValue}")"
	fi

	echo "$value"
	exit 0
}

install() {
  echo "[INSTALL] => Get Easya files..."
  curl -fLSs https://github.com/Easya-Solutions/dolibarr/archive/${DOLI_VERSION}.tar.gz | tar -C /tmp -xz
  cp -r /tmp/dolibarr-${DOLI_VERSION}/* /var/www/html/
  rm -rf /tmp/*
  mkdir -p /var/www/documents
  mkdir -p /var/www/html/htdocs/custom
  chown -R www-data:www-data /var/www

  echo "[INSTALL] => Set Easya config..."
  cat > /var/www/html/htdocs/conf/conf.php << EOF
<?php
\$dolibarr_main_url_root='${DOLI_URL_ROOT}';
\$dolibarr_main_document_root='/var/www/html/htdocs';
\$dolibarr_main_url_root_alt='/custom';
\$dolibarr_main_document_root_alt='/var/www/html/htdocs/custom';
\$dolibarr_main_data_root='/var/www/documents';
\$dolibarr_main_db_host='${DOLI_DB_HOST}';
\$dolibarr_main_db_port='${DOLI_DB_HOST_PORT}';
\$dolibarr_main_db_name='${DOLI_DB_NAME}';
\$dolibarr_main_db_prefix='llx_';
\$dolibarr_main_db_user='${DOLI_DB_USER}';
\$dolibarr_main_db_pass='${DOLI_DB_PASSWORD}';
\$dolibarr_main_db_type='${DOLI_DB_TYPE}';
\$dolibarr_main_db_character_set='utf8';
\$dolibarr_main_db_collation='utf8_unicode_ci';
\$dolibarr_main_instance_unique_id='$(openssl rand -hex 64)';
\$dolibarr_main_authentication='dolibarr';
\$dolibarr_main_prod='1';
\$dolibarr_main_restrict_os_commands='mysqldump, mysql, pg_dump, pgrestore';
\$dolibarr_main_restrict_ip='';
\$dolibarr_nocsrfcheck='1';
\$dolibarr_cron_allow_cli='0';

EOF
  chown www-data:www-data /var/www/html/htdocs/conf/conf.php
  
  echo "[INSTALL] => Install Easya..."
  cd /var/www/html/htdocs/install
  su www-data -s '/bin/sh' -c 'php step2.php set fr_FR'
  su www-data -s '/bin/sh' -c 'php step4.php fr_FR'
  su www-data -s '/bin/sh' -c "php step5.php 0.0.0 0.0.0 fr_FR set '$DOLI_ADMIN_LOGIN' '$DOLI_ADMIN_PASSWORD' '$DOLI_ADMIN_PASSWORD'"
  cd -
  touch /var/www/documents/install.lock

  echo "[INSTALL] => Set some default consts..."
  mysql -u "$DOLI_DB_USER" -p"$DOLI_DB_PASSWORD" -h "$DOLI_DB_HOST" -P "$DOLI_DB_HOST_PORT" "$DOLI_DB_NAME" -e "INSERT INTO llx_const (name, value, type, visible, note, entity) VALUES ('CRON_KEY', '$DOLI_CRON_KEY', 'chaine', 0, 'Added by auto installation', 0);" > /dev/null 2>&1
}

initDolibarr() {
  CURRENT_UID=$(id -u www-data)
  CURRENT_GID=$(id -g www-data)
  adduser -u "$WWW_USER_ID" -S www-data
  addgroup -g "$WWW_GROUP_ID" -S www-data
  addgroup www-data www-data

  if [ ! -d /var/www/documents ]; then
    echo "[INIT] => create volume directory /var/www/documents ..."
    mkdir -p /var/www/documents
  fi

  echo "[INIT] => update PHP Config ..."
  cat > "$PHP_INI_DIR/conf.d/dolibarr-php.ini" << EOF
date.timezone = ${PHP_INI_DATE_TIMEZONE}
sendmail_path = /usr/sbin/sendmail -t -i
memory_limit = ${PHP_INI_MEMORY_LIMIT}
EOF

  if ! [ -f /var/www/html/htdocs/conf/conf.php ]; then
    install
  fi

  echo "[INIT] => update ownership for file in Dolibarr Config ..."
  chown www-data:www-data /var/www/html/htdocs/conf/conf.php
  if ! [ -f /var/www/documents/install.lock ]; then
    chmod 600 /var/www/html/htdocs/conf/conf.php
  else
    chmod 400 /var/www/html/htdocs/conf/conf.php
  fi

  chown www-data /proc/self/fd/1
  chown www-data /proc/self/fd/2

  if [ "$CURRENT_UID" -ne "$WWW_USER_ID" ] || [ "$CURRENT_GID" -ne "$WWW_GROUP_ID" ]; then
    # Refresh file ownership cause it has changed
    echo "[INIT] => As UID / GID have changed from default, update ownership for files in /var/ww ..."
    chown -R www-data:www-data /var/www
  else
    # Reducing load on init : change ownership only for volumes declared in docker
    echo "[INIT] => update ownership for files in /var/www/documents ..."
    chown -R www-data:www-data /var/www/documents
  fi
}

DOLI_DB_USER=$(get_env_value 'DOLI_DB_USER' 'doli')
DOLI_DB_PASSWORD=$(get_env_value 'DOLI_DB_PASSWORD' 'doli_pass')
DOLI_ADMIN_LOGIN=$(get_env_value 'DOLI_ADMIN_LOGIN' 'admin')
DOLI_ADMIN_PASSWORD=$(get_env_value 'DOLI_ADMIN_PASSWORD' 'admin')

initDolibarr

set -e

if [ "${1#-}" != "$1" ]; then
  set -- php-fpm "$@"
fi

exec "$@"
