#!/bin/bash
set -e

# === VARIABILI ===
ODOO_BRANCH="16.0"
ODOO_DIR="$HOME/odoo"
ODOO_CONF="$HOME/.odoo/odoo.conf"
PG_DIR="$HOME/.pgsql"
PG_PORT=5434
ODOO_PORT=8069

PYTHON_BIN="/usr/bin/python3.11"
PYTHON_LIBS="~/blendx-leonardo-notify/py17/lib/python3.11/site-packages"
REPO_URL="https://github.com/hurrinico/apt.git"
REPO_DIR="$HOME/install_files"

mkdir -p ~/.odoo
mkdir -p "$PG_DIR"

# === CLONE / PULL REPO FILES ===
if [ ! -d "$REPO_DIR" ]; then
    echo ">>> Clono repo con file di installazione..."
    git clone "$REPO_URL" "$REPO_DIR"
else
    echo ">>> Aggiorno repo locale..."
    cd "$REPO_DIR"
    git pull
fi

# === Clona Odoo ===
echo ">>> Clonazione/aggiornamento Odoo $ODOO_BRANCH"
if [ ! -d "$ODOO_DIR" ]; then
    git clone --depth 1 --branch $ODOO_BRANCH https://github.com/odoo/odoo.git "$ODOO_DIR"
else
    cd "$ODOO_DIR"
    git pull
fi

# === PostgreSQL installazione da sorgente locale ===
cd "$PG_DIR"
if [ ! -d "$PG_DIR/bin" ]; then
    echo ">>> Installazione PostgreSQL da file locale..."
    tar -xf "$REPO_DIR/postgresql-15.6.tar.gz"
    cd postgresql-15.6
    ./configure --prefix="$PG_DIR"
    make -j$(nproc)
    make install
    cd ..
    "$PG_DIR/bin/initdb" -D "$PG_DIR/data"
fi

echo ">>> Avvio PostgreSQL user-mode (porta $PG_PORT)..."
"$PG_DIR/bin/pg_ctl" -D "$PG_DIR/data" -o "-p $PG_PORT" -l "$PG_DIR/logfile" start
sleep 3
"$PG_DIR/bin/createuser" -p $PG_PORT -s $(whoami) || true
"$PG_DIR/bin/createdb" -p $PG_PORT odoo16 || true

# === Configurazione odoo.conf ===
cat > "$ODOO_CONF" <<EOF
[options]
addons_path = $ODOO_DIR/addons
admin_passwd = admin
db_host = 127.0.0.1
db_port = $PG_PORT
db_user = $(whoami)
db_password =
logfile = ~/.odoo/odoo.log
xmlrpc_port = $ODOO_PORT
EOF

# === Script di avvio per includere PYTHONPATH ===
cat > "$ODOO_DIR/start.sh" <<EOF
#!/bin/bash
export PYTHONPATH=$PYTHON_LIBS:\$PYTHONPATH
exec $PYTHON_BIN $ODOO_DIR/odoo-bin -c $ODOO_CONF "\$@"
EOF

chmod +x "$ODOO_DIR/start.sh"

# === Setup systemd user service ===
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/odoo.service <<EOF
[Unit]
Description=Odoo 16 Service (no venv)
After=network.target

[Service]
ExecStart=$ODOO_DIR/start.sh
WorkingDirectory=$ODOO_DIR
Restart=always
User=$USER
Environment=PYTHONPATH=$PYTHON_LIBS

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reexec || true
systemctl --user daemon-reload
systemctl --user enable --now odoo.service

echo "✅ Installazione completata. Odoo è in esecuzione!"
echo "Usa 'journalctl --user -u odoo -f' per vedere i log."
