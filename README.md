# NextDNS Blocker Service

A simple Bash-based service that monitors a JSON configuration file to:
- Kill (block) specified desktop applications during configured "blocked times".
- Update the NextDNS denylist for specified websites via API calls.
- Log all actions and events.
- Send desktop notifications to alert the user when a blocked application is launched.

## Features

- **JSON Configuration Driven:**
  Configure blocked apps, websites, blocked time period, and NextDNS settings.

- **Application Blocking:**
  If a blocked application is detected during the blocked time, it will be terminated, and an attempt is logged and notified.

- **NextDNS API Integration:**
  The service updates the NextDNS denylist to block specified websites during blocked time and deactivates them otherwise.

- **Logging:**
  All events are logged to a file specified in the JSON configuration.

- **Desktop Notification:**
  When an attempt is made to run a blocked application, the target user receives a desktop notification.

## Requirements

- Linux (Ubuntu or similar)
- `bash`, `jq`, `curl`, and `notify-send` (part of the `libnotify-bin` package)

## Installation

1. **Clone this repository.**

2. **Create your configuration file:**

   Create a file at `/root/blocker_config.json` (or update the path in `blocker_service.sh`) with your settings. You can start by copying the sample file:

   ```bash
   cp blocker_config.sample.json /root/blocker_config.json
   ```

   Then edit `/root/blocker_config.json` to include your real values. **Do not publish your real API key publicly!**

3. **Make the script executable:**

   ```bash
   chmod +x blocker_service.sh
   ```

4. **Test the script manually:**

   ```bash
   sudo ./blocker_service.sh
   ```

   Check the log file (e.g., `/var/log/blocker.log`) and your desktop notifications.

## Running as a Service

To run the service continuously in the background, set up a systemd unit file.

Create a file `/etc/systemd/system/blocker.service` with the following content:

```ini
[Unit]
Description=NextDNS Blocker Service
After=network.target

[Service]
Type=simple
ExecStart=/root/blocker_service.sh
Restart=always
User=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
```

Then reload systemd and enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable blocker.service
sudo systemctl start blocker.service
```

Check its status with:

```bash
sudo systemctl status blocker.service
```

## License

This project is licensed under the MIT License.

## Disclaimer

**Warning:** Running scripts as root, especially those that kill processes and update network settings, can have unintended consequences. Always review and test the code in a safe environment before using it in production.

Also, do not publish your actual NextDNS API key with your public repository. Use sample configurations with dummy values or use secure methods (such as environment variables) to manage your credentials.
```
