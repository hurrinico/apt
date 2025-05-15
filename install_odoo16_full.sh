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

mkdir -p ~/.odoo
mkdir -p "$PG_DIR"

echo ">>> [1/6] Controllo/Installazione pip"
if ! command -v pip3 >/dev/null 2>&1; then
    echo ">>> pip3 non trovato. Installazione..."
    curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python3 get-pip.py --user
    export PATH="$HOME/.local/bin:$PATH"
fi

echo ">>> [2/6] Clonazione Odoo $ODOO_BRANCH"
if [ ! -d "$ODOO_DIR" ]; then
    git clone --depth 1 --branch $ODOO_BRANCH https://github.com/odoo/odoo.git "$ODOO_DIR"
fi

echo ">>> [3/6] Virtualenv Python"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel

echo ">>> [4/6] Installazione dipendenze Odoo"
pip install -r "$ODOO_DIR/requirements.txt"

echo ">>> [5/6] Installazione PostgreSQL local (no root)"
cd "$PG_DIR"
if [ ! -d "$PG_DIR/bin" ]; then
    echo ">>> Scarico PostgreSQL 15..."
    curl -LO https://ftp.postgresql.org/pub/source/v15.6/postgresql-15.6.tar.gz
    tar -xf postgresql-15.6.tar.gz
    cd postgresql-15.6
    ./configure --prefix="$PG_DIR"
    make -j$(nproc)
    make install
    cd ..
    "$PG_DIR/bin/initdb" -D "$PG_DIR/data"
    echo ">>> PostgreSQL inizializzato in $PG_DIR/data"
fi

echo ">>> Avvio PostgreSQL user-mode (porta $PG_PORT)..."
"$PG_DIR/bin/pg_ctl" -D "$PG_DIR/data" -o "-p $PG_PORT" -l "$PG_DIR/logfile" start
sleep 3
"$PG_DIR/bin/createuser" -p $PG_PORT -s $(whoami) || true
"$PG_DIR/bin/createdb" -p $PG_PORT odoo16 || true

echo ">>> [6/6] Generazione odoo.conf"
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

echo ">>> Installazione completata!"
echo "Puoi avviare Odoo con:"
echo "source $VENV_DIR/bin/activate && $ODOO_DIR/odoo-bin -c $ODOO_CONF"

echo ">>> Copio file systemd per esecuzione automatica (user service)..."
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

echo ">>> Abilitazione systemd --user (avvio automatico Odoo)"
systemctl --user daemon-reexec || true
systemctl --user daemon-reload
systemctl --user enable --now odoo.service

echo "✅ Odoo 16 è in esecuzione come servizio utente!"
echo "🔍 Log: journalctl --user -u odoo -f"
