#!/bin/bash
set -e

# === VARIABILI ===
ODOO_BRANCH="16.0"
ODOO_DIR="$HOME/odoo"
ODOO_CONF="$HOME/.odoo/odoo.conf"
VENV_DIR="$HOME/odoo16env"
PG_DIR="$HOME/.pgsql"
PG_PORT=5434
ODOO_PORT=8069

# Inserisci qui l’URL del tuo repo pubblico (che contiene get-pip.py e postgresql-15.6.tar.gz)
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

# === pip install da file locale ===
echo ">>> Controllo pip3"
if ! command -v pip3 >/dev/null 2>&1; then
    echo ">>> pip3 non trovato. Installo da file locale..."
    python3 "$REPO_DIR/get-pip.py" --user
    export PATH="$HOME/.local/bin:$PATH"
fi

# === Clona Odoo ===
echo ">>> Clonazione/aggiornamento Odoo $ODOO_BRANCH"
if [ ! -d "$ODOO_DIR" ]; then
    git clone --depth 1 --branch $ODOO_BRANCH https://github.com/odoo/odoo.git "$ODOO_DIR"
else
    cd "$ODOO_DIR"
    git pull
fi

# === Virtualenv e dipendenze ===
echo ">>> Setup virtualenv Python"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# Aggiungi pg_config nel PATH
export PATH="$PG_DIR/bin:$PATH"

pip install --upgrade pip setuptools wheel

# Usa psycopg2-binary modificando requirements temporaneamente
sed -i 's/^psycopg2==2.8.6/psycopg2-binary==2.8.6/' "$ODOO_DIR/requirements.txt"

pip install -r "$ODOO_DIR/requirements.txt"

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

echo ">>> Setup systemd user service"
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/odoo.service <<EOF
[Unit]
Description=Odoo 16 Service
After=network.target

[Service]
ExecStart=$VENV_DIR/bin/python3 $ODOO_DIR/odoo-bin -c $ODOO_CONF
WorkingDirectory=$ODOO_DIR
Restart=always
User=$USER
Environment=PATH=$VENV_DIR/bin:$PATH

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reexec || true
systemctl --user daemon-reload
systemctl --user enable --now odoo.service

echo "✅ Installazione completata. Odoo è in esecuzione!"
echo "Usa 'journalctl --user -u odoo -f' per vedere i log."

