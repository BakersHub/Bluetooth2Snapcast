#!/usr/bin/env python3
"""
Stream audio from Bluetooth to Snapcast server via TCP
Captures audio from bluetooth_to_snapcast sink and sends to Snapcast server
"""
import subprocess
import socket
import time
import logging
import signal
import sys

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class AudioStreamer:
    def __init__(self, server_host='192.168.0.30', server_port=4951):
        self.server_host = server_host
        self.server_port = server_port
        self.running = True
        self.process = None
        
    def stream_audio(self):
        """Stream audio from PulseAudio to Snapcast server via TCP"""
        logger.info(f"Starting audio stream to {self.server_host}:{self.server_port}")
        
        # Use parec to capture from the monitor source and pipe to TCP
        command = [
            'parec',
            '--format=s16le',
            '--rate=48000',
            '--channels=2',
            '--latency-msec=100',
            '--device=snapcast_to_bluetooth.monitor'
        ]
        
        while self.running:
            try:
                # Connect to Snapcast server
                logger.info(f"Connecting to Snapcast server...")
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.connect((self.server_host, self.server_port))
                logger.info(f"Connected to {self.server_host}:{self.server_port}")
                
                # Start capturing audio
                self.process = subprocess.Popen(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                
                # Stream audio data
                while self.running:
                    data = self.process.stdout.read(4096)
                    if not data:
                        break
                    sock.sendall(data)
                    
            except (ConnectionRefusedError, ConnectionResetError, BrokenPipeError) as e:
                logger.error(f"Connection error: {e}")
                if self.process:
                    self.process.terminate()
                if self.running:
                    logger.info("Retrying in 5 seconds...")
                    time.sleep(5)
            except Exception as e:
                logger.error(f"Unexpected error: {e}")
                if self.running:
                    time.sleep(5)
            finally:
                try:
                    sock.close()
                except:
                    pass
    
    def cleanup(self):
        """Clean up resources"""
        logger.info("Cleaning up...")
        self.running = False
        if self.process:
            self.process.terminate()
            self.process.wait()
    
    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        logger.info(f"Received signal {signum}")
        self.cleanup()
        sys.exit(0)

def main():
    streamer = AudioStreamer(server_host='192.168.0.30', server_port=4951)
    
    signal.signal(signal.SIGINT, streamer.signal_handler)
    signal.signal(signal.SIGTERM, streamer.signal_handler)
    
    try:
        streamer.stream_audio()
    finally:
        streamer.cleanup()

if __name__ == "__main__":
    main()
