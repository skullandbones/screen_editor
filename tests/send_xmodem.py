#!/usr/bin/env python3
"""
Automated XMODEM file sender for real CP/M hardware over serial port.
Uses pyserial and xmodem in the repository virtual environment.
"""

import sys
import os
import time
import serial
from xmodem import XMODEM

def progress_callback(total_packets, success_count, error_count):
    sys.stdout.write(f"\r[*] XMODEM progress: {success_count} packets sent (errors: {error_count})")
    sys.stdout.flush()

def send_file(port="/dev/ttyUSB0", baudrate=115200, filepath=None):
    if not filepath or not os.path.isfile(filepath):
        print(f"[-] File not found: {filepath}")
        return False

    print(f"[*] Opening serial port {port} at {baudrate} bps...")
    ser = serial.Serial(port, baudrate, timeout=3.0)

    def getc(size, timeout=1):
        ser.timeout = timeout
        return ser.read(size) or None

    def putc(data, timeout=1):
        ser.timeout = timeout
        return ser.write(data)

    modem = XMODEM(getc, putc, mode='xmodem1k')

    print(f"[*] Sending '{filepath}' ({os.path.getsize(filepath)} bytes)...")
    print("[*] Waiting for receiver NAK/CRC handshake from CP/M XM.COM...")

    with open(filepath, 'rb') as fp:
        status = modem.send(fp, callback=progress_callback)

    print("")
    ser.close()

    if status:
        print(f"[+] Transfer completed successfully: '{filepath}' transferred.")
        return True
    else:
        print("[-] Transfer failed.")
        return False

if __name__ == "__main__":
    target_file = sys.argv[1] if len(sys.argv) > 1 else "SE.COM"
    port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyUSB0"
    success = send_file(port=port, filepath=target_file)
    sys.exit(0 if success else 1)
