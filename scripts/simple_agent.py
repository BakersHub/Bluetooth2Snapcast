#!/usr/bin/env python3
"""
Simple Bluetooth Agent - Auto-accepts all pairing requests
"""
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = 'org.bluez'
AGENT_INTERFACE = 'org.bluez.Agent1'
AGENT_PATH = "/test/agent"

class Agent(dbus.service.Object):
    """Bluetooth agent that auto-accepts all pairing requests"""
    
    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Release(self):
        print("Release")

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        print(f"AuthorizeService ({device}, {uuid}) - Auto-accepting")
        return

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        print(f"RequestPinCode ({device}) - Returning 0000")
        return "0000"

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        print(f"RequestPasskey ({device}) - Returning 0")
        return dbus.UInt32(0)

    @dbus.service.method(AGENT_INTERFACE, in_signature="ou", out_signature="")
    def DisplayPasskey(self, device, passkey):
        print(f"DisplayPasskey ({device}, {passkey:06d})")

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        print(f"DisplayPinCode ({device}, {pincode})")

    @dbus.service.method(AGENT_INTERFACE, in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        print(f"RequestConfirmation ({device}, {passkey:06d}) - AUTO-ACCEPTING WITHOUT USER INPUT")
        # Automatically return without waiting for confirmation
        return

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        print(f"RequestAuthorization ({device}) - AUTO-ACCEPTING WITHOUT USER INPUT")
        # Automatically return without waiting for authorization
        return

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Cancel(self):
        print("Cancel")

if __name__ == '__main__':
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    bus = dbus.SystemBus()
    agent = Agent(bus, AGENT_PATH)

    obj = bus.get_object(BUS_NAME, "/org/bluez")
    manager = dbus.Interface(obj, "org.bluez.AgentManager1")
    
    # Register with NoInputNoOutput capability - no user interaction required
    manager.RegisterAgent(AGENT_PATH, "NoInputNoOutput")
    print("Agent registered with NoInputNoOutput capability")
    
    # Set as default agent
    manager.RequestDefaultAgent(AGENT_PATH)
    print("Set as default agent - ALL pairing will be auto-accepted without prompts")

    mainloop = GLib.MainLoop()
    mainloop.run()
