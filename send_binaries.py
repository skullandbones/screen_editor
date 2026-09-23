#!/usr/bin/env python3
"""
send_binaries.py - Automated Serial Binary & Plugin Uploader for RomWBW CP/M 2.2
Specifically designed for SC131 / RC2014 systems communicating over serial UART.

Strategy:
  1. Ping CP/M console with CR / drive switch command to confirm prompt is at J:
  2. For each binary (SE.COM and plugins/*.{OVL,PRL}):
     - Send command: A:XM R <FILENAME>
     - Consume the command echo and XM.COM banner text for 3 seconds
     - Start Python XMODEM-1K transfer over serial with hardware flow control (RTS/CTS)
     - Wait for CP/M to return to the J: prompt before initiating next file
"""

import os
import sys
import time
import argparse
import glob

# Auto re-exec with virtual environment python if available and not already in venv
script_dir = os.path.dirname(os.path.abspath(__file__))
venv_python = os.path.join(script_dir, ".venv", "bin", "python3")
if os.path.isfile(venv_python) and sys.prefix == sys.base_prefix:
    os.execv(venv_python, [venv_python] + sys.argv)


try:
    import serial
except ImportError:
    print("[-] Error: 'pyserial' is not installed.")
    print("    Please run: source .venv/bin/activate && pip install pyserial xmodem")
    sys.exit(1)

try:
    from xmodem import XMODEM
except ImportError:
    print("[-] Error: 'xmodem' is not installed.")
    print("    Please run: source .venv/bin/activate && pip install pyserial xmodem")
    sys.exit(1)


def progress_callback(total_packets, success_count, error_count):
    """Live XMODEM-1K progress display."""
    kb_sent = success_count  # 1K packets = 1 KB per packet
    sys.stdout.write(f"\r    -> {kb_sent} KB sent (packets: {success_count}, errors: {error_count})")
    sys.stdout.flush()


def discover_binaries(base_dir):
    """
    Discovers SE.COM and all available binary plugins (.OVL and .PRL)
    in base_dir and plugins/ subdirectory.
    """
    binaries = []

    # 1. Main editor binary: SE.COM
    se_com = os.path.join(base_dir, "SE.COM")
    if os.path.isfile(se_com):
        binaries.append(se_com)

    # 2. Plugins in plugins/ directory (.OVL and .PRL, case-insensitive)
    plugins_dir = os.path.join(base_dir, "plugins")
    if os.path.isdir(plugins_dir):
        patterns = ["*.OVL", "*.ovl", "*.PRL", "*.prl"]
        found = set()
        for pat in patterns:
            for p in glob.glob(os.path.join(plugins_dir, pat)):
                if os.path.isfile(p):
                    found.add(os.path.abspath(p))
        binaries.extend(sorted(found))

    return binaries


def ping_cpm_drive(ser, target_drive="J:", max_retries=3, timeout=3.0):
    """
    Step 1 Strategy:
    Pings the CP/M console with carriage returns, commands it to switch
    to the target drive, and confirms that the prompt (e.g. 'J>') is active.
    """
    drv = target_drive.upper().rstrip(":")
    expected_prompt = f"{drv}>".encode("ascii")

    print(f"[*] [Step 1] Pinging CP/M console to confirm prompt at {drv}: drive...")

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    for attempt in range(1, max_retries + 1):
        # 1. Send CR to wake up CCP and obtain prompt
        ser.write(b"\r\n")
        time.sleep(0.3)

        # 2. Issue drive switch command (e.g. "J:\r")
        ser.write(f"{drv}:\r".encode("ascii"))

        t0 = time.time()
        buf = b""
        while time.time() - t0 < timeout:
            if ser.in_waiting:
                chunk = ser.read(ser.in_waiting)
                buf += chunk
                if expected_prompt in buf:
                    time.sleep(0.1)
                    if ser.in_waiting:
                        buf += ser.read(ser.in_waiting)
                    # Extract last line for confirmation display
                    last_line = buf.decode("ascii", errors="replace").strip().splitlines()[-1]
                    print(f"[+] Ping successful! Confirmed CP/M prompt: '{last_line}' (Drive {drv}: active)")
                    ser.reset_input_buffer()
                    return True
            time.sleep(0.05)

        print(f"[-] Ping attempt {attempt}/{max_retries} timed out waiting for '{drv}>'. Retrying...")
        ser.reset_input_buffer()

    print(f"[-] Error: Could not confirm CP/M prompt at {drv}: drive after {max_retries} attempts.")
    print("    Tip: Check serial cable, baud rate (115200), and ensure SBC is powered on and at CP/M prompt.")
    return False


def consume_xm_banner(ser, duration=3.0):
    """
    Step 2 Strategy:
    Consumes the XM command echo and startup banner text for `duration` seconds
    so that the serial receive buffer is completely free of text before Python
    XMODEM starts.

    Returns (banner_text, pre_captured_handshake_byte)
    """
    print(f"    -> Consuming XM banner text for {duration:.1f} seconds...")
    t_end = time.time() + duration
    raw = bytearray()
    while time.time() < t_end:
        if ser.in_waiting:
            chunk = ser.read(ser.in_waiting)
            raw.extend(chunk)
        time.sleep(0.05)

    handshake = None
    # Check if XM has already emitted a handshake byte ('C' or NAK 0x15) at the very end
    # Note: RomWBW XM may emit 'C' (0x43) followed by 'K' (0x4B) for 1K announcement
    if len(raw) >= 2 and raw[-2] == 0x43 and raw[-1] == 0x4B:  # 'CK'
        handshake = b'C'
        raw = raw[:-2]
    elif len(raw) >= 1 and raw[-1] in (0x43, 0x15):            # 'C' or NAK
        handshake = bytes([raw[-1]])
        raw = raw[:-1]

    banner_text = raw.decode("ascii", errors="replace").strip()
    return banner_text, handshake


def wait_for_cpm_prompt(ser, target_drive="J:", timeout=5.0):
    """
    Waits for CP/M to return to the command prompt (e.g. 'J>')
    after XM.COM finishes file reception and exits.
    """
    drv = target_drive.upper().rstrip(":")
    expected = f"{drv}>".encode("ascii")
    t0 = time.time()
    buf = b""
    while time.time() - t0 < timeout:
        if ser.in_waiting:
            buf += ser.read(ser.in_waiting)
            if expected in buf:
                return True
        time.sleep(0.05)

    # Try poking console with CR if prompt not seen yet
    ser.write(b"\r")
    time.sleep(0.3)
    if ser.in_waiting:
        buf += ser.read(ser.in_waiting)
        if expected in buf:
            return True
    return False


def erase_cpm_file(ser, filename, target_drive="J:", timeout=3.0):
    """
    Erases target file on CP/M target drive before XM transfer,
    since RomWBW XM.COM will not overwrite existing files.
    """
    drv = target_drive.upper().rstrip(":")
    print(f"    -> Erasing existing {drv}:{filename} if present...")
    ser.reset_input_buffer()
    ser.write(f"ERA {filename}\r".encode("ascii"))
    time.sleep(0.3)
    # Wait for CP/M prompt (handles both deletion and 'NO FILE' responses)
    wait_for_cpm_prompt(ser, target_drive=target_drive, timeout=timeout)
    ser.reset_input_buffer()



def send_batch(port="/dev/ttyUSB0", baudrate=115200, target_drive="J:",
               xm_drive="A:", files=None, erase=True):
    if not files:
        print("[-] No files specified for transfer.")
        return False

    for f in files:
        if not os.path.isfile(f):
            print(f"[-] File not found: {f}")
            return False

    print("============================================================")
    print("   SC131 / RomWBW CP/M 2.2 Serial Binary Batch Uploader")
    print("============================================================")
    print(f"[*] Serial Port          : {port}")
    print(f"[*] Baud Rate            : {baudrate} bps")
    print(f"[*] Hardware Flow Control: ENABLED (RTS/CTS = True)")
    print(f"[*] Target Drive         : {target_drive}")
    print(f"[*] XM Utility Drive     : {xm_drive}")
    print(f"[*] Erase Existing Files : {'YES' if erase else 'NO'}")
    print(f"[*] Total Files to Send  : {len(files)}")
    print("------------------------------------------------------------")
    for idx, f in enumerate(files, 1):
        size = os.path.getsize(f)
        print(f"  {idx:2d}. {os.path.basename(f):<16} ({size:>6d} bytes) [{f}]")
    print("============================================================\n")

    try:
        ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1.0,
            rtscts=True,        # Hardware Flow Control (RTS/CTS)
            dsrdtr=False,
            xonxoff=False
        )
        ser.rts = True
        ser.dtr = True
    except serial.SerialException as e:
        print(f"[-] Failed to open serial port {port}: {e}")
        print("    Tip: Ensure Minicom or any other serial terminal application is closed.")
        return False

    time.sleep(0.5)

    # Step 1: Ping console and verify target drive prompt
    if not ping_cpm_drive(ser, target_drive=target_drive):
        ser.close()
        return False

    start_time = time.time()
    total_bytes_sent = 0

    # Step 2: Transfer each file sequentially
    for idx, filepath in enumerate(files, 1):
        filename = os.path.basename(filepath).upper()
        filesize = os.path.getsize(filepath)

        print(f"\n[{idx}/{len(files)}] Transferring {filename} ({filesize} bytes)...")

        # 1. Erase destination file on CP/M target drive (XM refuses to overwrite existing files)
        if erase:
            erase_cpm_file(ser, filename, target_drive=target_drive)

        # 2. Send command to start XM receiver
        xm_cmd = f"{xm_drive}XM R {filename}\r".encode("ascii")
        ser.write(xm_cmd)
        print(f"    -> Sent command: {xm_drive}XM R {filename}")

        # 3. Consume XM banner text for 3 seconds
        banner_text, pre_handshake = consume_xm_banner(ser, duration=3.0)
        if banner_text:
            for bline in banner_text.splitlines():
                print(f"       | {bline}")

        # Check if XM reported an error (e.g. file exists, disk full, etc.)
        if "++ File exists" in banner_text or "++ Error" in banner_text:
            print(f"[-] XM reported error: Destination file could not be created!")
            ser.close()
            return False

        # 3. Setup XMODEM stream handlers
        initial_bytes = [pre_handshake] if pre_handshake else []

        def getc(size, timeout=1):
            if initial_bytes:
                return initial_bytes.pop(0)
            ser.timeout = timeout
            c = ser.read(size) or None
            # If XM emits 'C' followed by 'K' (1K protocol advertisement),
            # drain the 'K' so it does not collide with packet 1 ACK
            if c == b'C':
                time.sleep(0.04)
                if ser.in_waiting:
                    peek = ser.read(1)
                    if peek != b'K':
                        initial_bytes.append(peek)
            return c

        def putc(data, timeout=1):
            ser.timeout = timeout
            return ser.write(data)

        print("    -> Starting Python XMODEM transfer (RTS/CTS enabled, 1K blocks)...")
        modem = XMODEM(getc, putc, mode='xmodem1k')

        with open(filepath, "rb") as fp:
            success = modem.send(fp, retry=30, timeout=10, callback=progress_callback)

        print("")
        if not success:
            print(f"[-] FAILED to transfer {filename}! Aborting batch.")
            ser.close()
            return False

        print(f"[+] {filename} successfully transferred and verified.")
        total_bytes_sent += filesize

        # 4. Wait for CP/M to return to target drive prompt before sending next command
        print(f"    -> Waiting for CP/M {target_drive} prompt...")
        if not wait_for_cpm_prompt(ser, target_drive=target_drive, timeout=5.0):
            print(f"[-] Warning: Did not detect {target_drive} prompt after {filename}, flushing console...")
            ser.reset_input_buffer()
            ser.write(b"\r\n")
            time.sleep(0.5)

    elapsed = time.time() - start_time
    ser.close()

    rate_kbs = (total_bytes_sent / 1024.0) / elapsed if elapsed > 0 else 0
    print("\n============================================================")
    print(f"[+] Batch upload completed successfully!")
    print(f"[*] Files Transferred : {len(files)} to drive {target_drive}")
    print(f"[*] Total Data Sent   : {total_bytes_sent} bytes")
    print(f"[*] Elapsed Time      : {elapsed:.1f} seconds (~{rate_kbs:.1f} KB/s)")
    print("============================================================")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Transfer SE.COM and all binary plugins (.OVL/.PRL) to CP/M drive J: over serial."
    )
    parser.add_argument(
        "files",
        nargs="*",
        help="Optional specific files to transfer (default: auto-discover SE.COM and plugins/*.{OVL,PRL})"
    )
    parser.add_argument(
        "-p", "--port",
        default="/dev/ttyUSB0",
        help="Serial port device (default: /dev/ttyUSB0)"
    )
    parser.add_argument(
        "-b", "--baud",
        type=int,
        default=115200,
        help="Baud rate (default: 115200)"
    )
    parser.add_argument(
        "-d", "--drive",
        default="J:",
        help="Target CP/M destination drive (default: J:)"
    )
    parser.add_argument(
        "-x", "--xm-drive",
        default="A:",
        help="Drive containing XM.COM on CP/M (default: A:)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List discovered files to transfer and exit without opening serial port"
    )
    parser.add_argument(
        "--no-erase",
        action="store_false",
        dest="erase",
        default=True,
        help="Do not erase destination files on CP/M before transfer (default: erase existing files)"
    )

    args = parser.parse_args()

    # Determine files to send
    if args.files:
        target_files = [os.path.abspath(f) for f in args.files]
    else:
        target_files = discover_binaries(script_dir)

    if not target_files:
        print("[-] No binary files found to transfer!")
        print(f"    Looked for SE.COM in: {script_dir}")
        print(f"    Looked for *.OVL and *.PRL in: {os.path.join(script_dir, 'plugins')}")
        sys.exit(1)

    if args.dry_run:
        print("[*] Dry run mode. The following files would be transferred:")
        for idx, f in enumerate(target_files, 1):
            print(f"  {idx:2d}. {os.path.basename(f):<16} ({os.path.getsize(f)} bytes) [{f}]")
        sys.exit(0)

    # Normalize target drive letter (ensure trailing colon)
    drive = args.drive.upper()
    if not drive.endswith(":"):
        drive += ":"

    xm_drv = args.xm_drive.upper()
    if not xm_drv.endswith(":"):
        xm_drv += ":"

    success = send_batch(
        port=args.port,
        baudrate=args.baud,
        target_drive=drive,
        xm_drive=xm_drv,
        files=target_files,
        erase=args.erase
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
