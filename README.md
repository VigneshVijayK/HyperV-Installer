# Hyper-V Installer for Windows Home

Enable Hyper-V on Windows Home edition with a single command — no manual steps needed.

---

## ⚡ Quick Start

Open **PowerShell as Administrator** and paste:

```powershell
irm https://raw.githubusercontent.com/VigneshVijayK/HyperV-Installer/main/HyperV-Installer.ps1 | iex
```

> **How to open PowerShell as Administrator:**
> Press `Win + S` → type `PowerShell` → right-click → **Run as Administrator** → paste the command above → press Enter.

---

## 📋 What's Inside

| Option | Description |
|--------|-------------|
| **[1] Enable Hyper-V** | Installs Hyper-V on Windows Home using DISM |
| **[2] Check Status** | Shows whether Hyper-V is installed and running |
| **[3] Download VirtualBox** | Opens the VirtualBox download page (free alternative) |
| **[4] BIOS Guide** | Step-by-step guide to enable virtualization in BIOS |
| **[5] About** | Script information |
| **[0] Exit** | Closes the tool |

---

## 🖥️ Requirements

- Windows 10 or Windows 11 (Home edition)
- PowerShell 5.1 or later
- Administrator privileges
- Internet connection (for the one-liner only)
- Virtualization enabled in BIOS *(see Option 4 inside the tool if unsure)*

---

## 🔧 How to Use

### Step 1 — Run the script
Paste the one-liner into an Admin PowerShell. The tool will launch automatically.

### Step 2 — Check your system
The tool will display your OS, CPU, RAM and whether virtualization is enabled in your BIOS. If virtualization is disabled, use **Option 4** inside the tool for guidance before proceeding.

### Step 3 — Enable Hyper-V
Select **Option 1** and confirm when prompted. The tool will:
- Scan and inject Hyper-V packages using DISM
- Enable the Hyper-V feature
- Enable Hyper-V management tools

### Step 4 — Restart
A restart is required to complete installation. The tool will offer to restart automatically.

### Step 5 — Launch Hyper-V Manager
After reboot, press `Win + S` and search for **Hyper-V Manager**.

---

## ❓ Frequently Asked Questions

**Will this work on my PC?**
It works on most Windows 10 and Windows 11 Home systems. A small number of OEM builds may not include the required servicing files — if that's the case, Option 3 (VirtualBox) is a free alternative that works on all Windows editions.

**Is this safe?**
The script only uses Microsoft's built-in DISM tool to enable a feature that already exists in your Windows image. However, as with any system modification, it is good practice to create a restore point or backup beforehand.

**How do I create a restore point before running?**
Press `Win + S` → search **Create a restore point** → click **Create** → give it a name → click **Create**.

**Hyper-V Manager doesn't appear after reboot — what do I do?**
Run the script again and use **Option 2** to check the status. If features show as not installed, try Option 1 again. If the issue persists, check the log file at `%TEMP%\HyperV-Installer.log` for details.

**My PC says virtualization is disabled — what do I do?**
Use **Option 4** inside the tool. It provides step-by-step instructions and the correct BIOS key for your PC brand.

**I don't want to use Hyper-V — is there an alternative?**
Yes. Select **Option 3** to open the VirtualBox download page. VirtualBox is free, open-source, and works on all Windows editions without any system modifications.

---

## 📄 Log File

A log of all actions is saved automatically at:

```
%TEMP%\HyperV-Installer.log
```

Open it in Notepad if something goes wrong and you need to investigate.

---

## ⚠️ Disclaimer

This tool uses an unofficial method to enable Hyper-V on Windows Home. Microsoft does not officially support Hyper-V on Home edition. Use at your own risk. Always have a system backup or restore point before making system-level changes.
