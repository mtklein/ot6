#!/bin/sh
# Start the OT6 TLM's pieces on px13 at boot, as mtklein, with no login:
#   ot6-rc            claude remote-control in ~/ot6, reattaching (--continue)
#   ot6-live          live.py at http://px13:8611/ with the Macs as peers
#   ot6-critic-tunnel ssh tunnel to the mbp's ollama on localhost:11434
# Rerun after editing; it rewrites the units. Enables only; nothing starts now (the running rc and live.py stay as they are).
set -e
U="$HOME/.config/systemd/user"
mkdir -p "$U"

cat > "$U/ot6-rc.service" <<'EOF'
[Unit]
Description=OT6 TLM: claude remote-control in ~/ot6, reattaching to the last session

[Service]
WorkingDirectory=%h/ot6
# Wait for DNS so --continue does not fail on a cold network and fall through.
ExecStartPre=/bin/sh -c 'until getent hosts api.anthropic.com >/dev/null; do sleep 2; done'
# --continue only finds a session recorded here in the last ~4 hours; else start fresh.
ExecStart=/bin/sh -c '%h/.local/bin/claude rc --continue || exec %h/.local/bin/claude rc'
Restart=on-failure
RestartSec=15

[Install]
WantedBy=default.target
EOF

cat > "$U/ot6-live.service" <<'EOF'
[Unit]
Description=OT6 live.py worker viewer (http://px13:8611/)

[Service]
WorkingDirectory=%h/ot6
# Its GitHub checks rerun only every 10 minutes: start on a working network.
ExecStartPre=/bin/sh -c 'until getent hosts github.com >/dev/null; do sleep 2; done'
ExecStart=/usr/bin/python3 tools/stream/live.py --bind 0.0.0.0 --port 8611 --peer mbp.local --peer air.local
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

cat > "$U/ot6-critic-tunnel.service" <<'EOF'
[Unit]
Description=OT6 critic: ssh tunnel to ollama on the mbp (localhost:11434)

[Service]
ExecStart=/usr/bin/ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 11434:127.0.0.1:11434 mbp.local
Restart=always
RestartSec=30

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable ot6-rc.service ot6-live.service ot6-critic-tunnel.service
# Linger: run mtklein's user services at boot without anyone logging in.
loginctl enable-linger "$USER" || sudo loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
