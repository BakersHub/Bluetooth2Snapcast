#!/usr/bin/env python3
import subprocess
import time
import re

# Track current loopback state
current_loopback_id = None
current_bt_source = None

def get_bluetooth_source():
    try:
        result = subprocess.run(['pactl', 'list', 'sources', 'short'], 
                              capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if 'bluez_source' in line and 'a2dp_source' in line:
                return line.split()[1]
    except:
        pass
    return None

def loopback_exists():
    try:
        result = subprocess.run(['pactl', 'list', 'sink-inputs', 'short'], 
                              capture_output=True, text=True)
        return 'module-loopback' in result.stdout
    except:
        return False

def check_loopback_health(module_id):
    """Check if the loopback module is still active and working"""
    if not module_id:
        return False
    try:
        result = subprocess.run(['pactl', 'list', 'modules', 'short'], 
                              capture_output=True, text=True)
        # Check if our specific module ID still exists
        return str(module_id) in result.stdout
    except:
        return False

def create_loopback(bt_source):
    """Create loopback and return module ID"""
    try:
        result = subprocess.run(['pactl', 'load-module', 'module-loopback',
                          f'source={bt_source}', 'sink=snapcast_to_bluetooth'],
                          capture_output=True, text=True)
        if result.returncode == 0:
            module_id = result.stdout.strip()
            print(f"Loopback created with module ID: {module_id}")
            return module_id
    except Exception as e:
        print(f"Error creating loopback: {e}")
    return None

def remove_loopback(module_id):
    """Remove loopback module"""
    if module_id:
        try:
            subprocess.run(['pactl', 'unload-module', str(module_id)])
            print(f"Removed loopback module {module_id}")
        except Exception as e:
            print(f"Error removing loopback: {e}")

print("Auto-loopback service started with health monitoring")
while True:
    bt_source = get_bluetooth_source()
    
    if bt_source:
        # Check if source changed or loopback is broken
        if current_bt_source != bt_source:
            print(f"Found new Bluetooth source: {bt_source}")
            if current_loopback_id:
                remove_loopback(current_loopback_id)
            current_loopback_id = create_loopback(bt_source)
            current_bt_source = bt_source
        elif not check_loopback_health(current_loopback_id):
            print(f"Loopback to {bt_source} is broken, recreating...")
            if current_loopback_id:
                remove_loopback(current_loopback_id)
            current_loopback_id = create_loopback(bt_source)
    else:
        # No Bluetooth source available
        if current_loopback_id:
            print("No Bluetooth source, removing loopback")
            remove_loopback(current_loopback_id)
            current_loopback_id = None
            current_bt_source = None
    
    time.sleep(5)
