#!/bin/sh

set -e

echo "PATH=\$PATH:/usr/local/bin" > /var/spool/cron/crontabs/www-data
echo "*/5 * * * * /var/www/scripts/cron/cron_run_jobs.php ${DOLI_CRON_KEY} ${DOLI_CRON_USER} > /proc/1/fd/1 2> /proc/1/fd/2" > /var/spool/cron/crontabs/www-data

exec busybox crond -f -l 0 -L /dev/stdout
