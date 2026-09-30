#!/usr/bin/env python3
import json
import os

# Create auth file
auth_dir = os.path.expanduser("~/.clawdbot/agents/main/agent")
os.makedirs(auth_dir, exist_ok=True)

auth_data = {
    "farm": {
        "apiKey": "sk-local-farm"
    }
}

auth_file = os.path.join(auth_dir, "auth-profiles.json")
with open(auth_file, 'w') as f:
    json.dump(auth_data, f, indent=2)

print(f"Auth file created: {auth_file}")
print(json.dumps(auth_data, indent=2))
