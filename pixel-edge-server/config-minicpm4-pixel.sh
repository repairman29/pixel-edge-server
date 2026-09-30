#!/data/data/com.termux/files/usr/bin/bash
# Config for miniCPM4 on Pixel

cat > ~/.clawdbot/clawdbot.json << 'EOF'
{
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan"
  },
  "agents": {
    "defaults": {
      "maxConcurrent": 4,
      "model": {
        "primary": "farm/minicpm4"
      },
      "workspace": "/data/data/com.termux/files/home/JARVIS/jarvis"
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      }
    }
  },
  "models": {
    "providers": {
      "farm": {
        "baseUrl": "http://127.0.0.1:8889/v1",
        "models": [
          {
            "id": "minicpm4",
            "name": "MiniCPM4 (Pixel)"
          }
        ]
      }
    }
  }
}
EOF

echo "Config updated for MiniCPM4 on Pixel"
grep '"primary"' ~/.clawdbot/clawdbot.json
