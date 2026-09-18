# Wi‑Fi Connect Script (nmcli)

A robust Bash script to connect to a Wi‑Fi network on Raspberry Pi (Debian Trixie, arm64/arm32) using `nmcli`. It ensures NetworkManager is running, verifies the SSID is broadcasted, checks for a saved profile, and then connects.

## Features

- Starts NetworkManager if it is not running.
- Waits for NetworkManager to become active before scanning.
- Checks if already connected to the SSID and exits early if so.
- Scans for the SSID and cancels if it is not broadcasted.
- Requires a saved connection profile; cancels if none exists.
- Uses `nmcli connection up` to connect via the saved profile.

## Requirements

- Raspberry Pi (Zero → Pi 5) running Debian Trixie (arm64 or arm32).
- `network-manager` and `nmcli` installed and enabled.
- A saved Wi‑Fi profile for the target SSID (created once with `nmcli device wifi connect`).

## Installation

1. Clone or download this repository to your Pi:

   ```bash
   cd ~
   git clone <your-repo-url>
   cd <repo-folder>
   ```

2. Make the script executable:

   ```bash
   chmod +x connect_wifi_profile.sh
   ```

3. (Optional) Move it to a directory in your PATH:

   ```bash
   sudo mv connect_wifi_profile.sh /usr/local/bin/connect-wifi
   sudo chmod +x /usr/local/bin/connect-wifi
   ```

## Usage

Edit the `ssid` variable at the top of the script to match your network:

```bash
ssid="Livebox-1234"
```

Then run:

```bash
sudo ./connect_wifi_profile.sh
# or, if installed in PATH:
sudo connect-wifi
```

### Creating the initial profile (first time only)

If you do not yet have a saved profile for your SSID, create one:

```bash
sudo nmcli device wifi connect "Livebox-1234" password "YOUR_PASSWORD" name "Livebox-1234"
```

After this, the script will find the profile and use it.

## Behavior

- If already connected → prints a message and exits with code 0.
- If NetworkManager cannot be started → exits with code 1.
- If SSID is not found in scans → exits with code 1.
- If no saved profile exists → exits with code 1.
- If connection fails → exits with code 1.
- On success → exits with code 0.

## Example output

```text
📡 Checking Wi‑Fi: Livebox-1234 ...
⚠️  NetworkManager is not running. Trying to start it...
✅ NetworkManager is running.
🔍 Scanning for broadcasted SSID: Livebox-1234 ...
✅ SSID is broadcasted: Livebox-1234
✅ Profile exists: Livebox-1234
🔌 Connecting to Livebox-1234 ...
✅ Connected to Livebox-1234
🏁 Done!
```

## Troubleshooting

- **“NetworkManager is not running”**  
  Ensure the service is enabled:  
  ```bash
  sudo systemctl enable NetworkManager
  sudo systemctl start NetworkManager
  ```

- **“Scanning not allowed while unavailable”**  
  This can happen right after starting NM. The script waits for NM to become active; if it persists, reboot the Pi or check that the Wi‑Fi device is up (`ip link`, `iw dev`).

- **SSID not found**  
  Confirm the AP is broadcasting and that your Pi’s Wi‑Fi supports the band (2.4 GHz vs 5 GHz).

## License

This project is provided as‑is. You may use and modify it freely.

## Author

Pascal (adapted for Raspberry Pi on Debian Trixie).
