# 🛠️ TMP Manager for cPanel

Readme: [EN](README.md)

![License](https://img.shields.io/github/license/sr00t3d/cpanel-tpm-manager)
![Shell Script](https://img.shields.io/badge/language-Bash-green.svg)

<img width="700" src="tmp-manager.webp" />

This Bash script was developed to monitor, clean, and resize the `/tmp` partition on servers running the **cPanel/WHM** control panel. It handles both virtual partitions (**tmpfs**) and physical loopback files (**tmpDSK**).

## ✨ Features

* **Real-Time Monitoring:** Checks current `/tmp` usage and displays detailed information.
* **Threshold Alerts:** Automatically identifies if usage has exceeded 80% (or the configured value).
* **Smart Cleanup:** Uses `tmpwatch` to remove files with more than 12 hours of inactivity.
* **Safety Backup:** Creates a full backup of `/tmp` files before resizing (on tmpfs systems).
* **Service Management:** Automatically stops and restarts MySQL/MariaDB to prevent file locks during unmounting.
* **Automated Resizing:** Supports the native cPanel `/scripts/securetmp` command.

---

## 🚀 Requirements

* **Operating System:** CloudLinux / AlmaLinux / Rocky Linux / CentOS (with cPanel).
* **Privileges:** **root** user access.
* **Dependencies:** * `tmpwatch` (usually preinstalled on cPanel).
* `systemd`.

---

## 🔒 Security and Best Practices

The script has been enhanced with the following security layers:

1. **Root Check:** Prevents execution by users without privileges.
2. **Lazy Unmount (`-l`):** Prevents the script from hanging if processes are still trying to access the partition.
3. **Attribute Preservation:** The `cp -a` command ensures that special `/tmp` permissions (Sticky Bit) are maintained in the backup.
4. **Logging:** All cleanup actions are recorded in `/var/log/tmp-manager.log`.

---

## 📖 How to Use

1. **Download the file to the server:**

```bash
curl -O https://raw.githubusercontent.com/sr00t3d/cpanel-tpm-manager/refs/heads/main/tmp-manager.sh

```

2. **Give execution permission:**

```bash
chmod +x tmp-manager.sh

```

3. **Execute the script:**

```bash
./tmp-manager.sh

```

Example:

```bash
./tmp-manager.sh

--- Partition Info ---
Mount Point: /tmp (/dev/loop0)
FS Type:     ext4
Usage:       1.3M / 505M (1%)
-----------------------

Allocating group tables: done                            
Writing inode tables: done                            
Writing superblocks and filesystem accounting information: done

tune2fs 1.46.5 (30-Dec-2021)
Creating journal inode: done
Done
Setting up /tmp... Done
Setting up /var/tmp... Done
Checking fstab for entries ...Done
Process Complete
Restarting mariadb.service...
✨ Procedure complete.
---
```

If the tmp is below the limit or full, resize it correctly.

---

## 🏗️ Script Structure

| Variable | Description |
| --- | --- |
| `TMP_ALERT_ENABLED` | Defines whether the script should suggest corrections based on usage (Default: `true`). |
| `ALERT_THRESHOLD` | Usage percentage that triggers the alert (Default: `80`). |
| `LOG_FILE` | Location where `tmpwatch` logs are saved. |
| `BACKUP_DIR` | Temporary directory in `/root` for file safekeeping. |

---

## ⚠️ Legal Notice

> [!WARNING]
> This software is provided "as is". Always ensure you have explicit permission before running. The author is not responsible for any misuse, legal consequences, or data impact caused by this tool.

## 📚 Detailed Tutorial

For a complete, step-by-step guide, check out my full article:

👉 [**Securely resize tmp on a cPanel server**](https://perciocastelo.com.br/blog/secure-resize-tmp-properly-on-a-cpanel-server.html)

## License 📄

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.