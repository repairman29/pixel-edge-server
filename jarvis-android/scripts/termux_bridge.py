#!/data/data/com.termux/files/usr/bin/python3
"""
Jarvis-Termux Bridge
Listens for commands from Jarvis Android app and executes them.
Run this in Termux: python3 jarvis_bridge.py
"""

import json
import os
import sys
import time
import subprocess
import signal
from pathlib import Path

# Configuration
COMMAND_DIR = Path("/sdcard/jarvis/commands")
RESULT_DIR = Path("/sdcard/jarvis/results")
LOG_FILE = Path("/sdcard/jarvis/bridge.log")
POLL_INTERVAL = 0.5  # seconds

# Ensure directories exist
COMMAND_DIR.mkdir(parents=True, exist_ok=True)
RESULT_DIR.mkdir(parents=True, exist_ok=True)

# Global flag for graceful shutdown
running = True

def log(msg):
    """Write to log file and stdout"""
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    global running
    log("Shutting down...")
    running = False

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

class CommandExecutor:
    """Execute various types of commands"""
    
    @staticmethod
    def execute_shell(command, cwd=None):
        """Execute shell command"""
        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                cwd=cwd,
                timeout=30
            )
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "code": result.returncode
            }
        except subprocess.TimeoutExpired:
            return {"success": False, "error": "Command timed out"}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def read_file(filepath):
        """Read file contents"""
        try:
            with open(filepath, 'r') as f:
                return {"success": True, "content": f.read()}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def write_file(filepath, content):
        """Write content to file"""
        try:
            Path(filepath).parent.mkdir(parents=True, exist_ok=True)
            with open(filepath, 'w') as f:
                f.write(content)
            return {"success": True, "message": f"Written to {filepath}"}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def list_directory(path):
        """List directory contents"""
        try:
            items = []
            for item in os.listdir(path):
                full_path = os.path.join(path, item)
                item_type = "dir" if os.path.isdir(full_path) else "file"
                items.append({"name": item, "type": item_type})
            return {"success": True, "items": items}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def get_system_info():
        """Get system information"""
        try:
            # Get disk usage
            df = subprocess.run("df -h", shell=True, capture_output=True, text=True)
            
            # Get memory info
            free = subprocess.run("free -h", shell=True, capture_output=True, text=True)
            
            # Get CPU info
            uptime = subprocess.run("uptime", shell=True, capture_output=True, text=True)
            
            return {
                "success": True,
                "disk": df.stdout,
                "memory": free.stdout,
                "uptime": uptime.stdout
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

def process_command(cmd_file):
    """Process a command file from Jarvis"""
    try:
        with open(cmd_file, 'r') as f:
            command = json.load(f)
        
        cmd_id = command.get("id", "unknown")
        cmd_type = command.get("type", "unknown")
        params = command.get("params", {})
        
        log(f"Processing command {cmd_id}: {cmd_type}")
        
        executor = CommandExecutor()
        
        # Execute based on command type
        if cmd_type == "shell":
            result = executor.execute_shell(params.get("command"), params.get("cwd"))
        
        elif cmd_type == "read_file":
            result = executor.read_file(params.get("path"))
        
        elif cmd_type == "write_file":
            result = executor.write_file(params.get("path"), params.get("content"))
        
        elif cmd_type == "list_dir":
            result = executor.list_directory(params.get("path", "/sdcard"))
        
        elif cmd_type == "system_info":
            result = executor.get_system_info()
        
        elif cmd_type == "ping":
            result = executor.execute_shell(f"ping -c 4 {params.get('host', 'google.com')}")
        
        elif cmd_type == "python":
            # Execute Python code
            code = params.get("code", "")
            result = executor.execute_shell(f"python3 -c '{code}'")
        
        else:
            result = {"success": False, "error": f"Unknown command type: {cmd_type}"}
        
        # Write result
        result_file = RESULT_DIR / f"{cmd_id}.json"
        with open(result_file, 'w') as f:
            json.dump({
                "id": cmd_id,
                "type": cmd_type,
                "result": result,
                "timestamp": time.time()
            }, f, indent=2)
        
        log(f"Command {cmd_id} completed")
        
        # Clean up command file
        cmd_file.unlink()
        
    except Exception as e:
        log(f"Error processing command: {e}")

def main():
    log("="*50)
    log("Jarvis-Termux Bridge Starting...")
    log(f"Command dir: {COMMAND_DIR}")
    log(f"Result dir: {RESULT_DIR}")
    log("="*50)
    
    # Process existing commands
    for cmd_file in COMMAND_DIR.glob("*.json"):
        log(f"Found existing command: {cmd_file.name}")
        process_command(cmd_file)
    
    # Main loop
    while running:
        try:
            # Check for new commands
            for cmd_file in COMMAND_DIR.glob("*.json"):
                process_command(cmd_file)
            
            time.sleep(POLL_INTERVAL)
            
        except Exception as e:
            log(f"Error in main loop: {e}")
            time.sleep(1)
    
    log("Bridge stopped.")

if __name__ == "__main__":
    main()