# Hyper-V Installer for Windows Home
### by [VigneshVijayK](https://github.com/VigneshVijayK)

An interactive PowerShell script to enable **Hyper-V on Windows Home** edition — with a single copy-paste command, just like winget or winactivator.

---

## ⚡ One-Line Install (Run in Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/VigneshVijayK/HyperV-Installer/main/HyperV-Installer.ps1 | iex
```

> **Right-click PowerShell → "Run as Administrator"**, then paste the command above.

---

## 📋 Features

| Option | Description |
|--------|-------------|
| **1** | Enable Hyper-V using DISM (force method for Windows Home) |
| **2** | Check current Hyper-V installation status |
| **3** | Download VirtualBox (free alternative) |
| **4** | BIOS/UEFI guide to enable virtualization |
| **5** | About / Developer info |

---

## 🚀 GitHub Setup Instructions

1. Create a new **public** GitHub repository named `HyperV-Installer`
2. Upload `HyperV-Installer.ps1` to the **root** of the repo
3. The raw URL will be:
   ```
   https://raw.githubusercontent.com/VigneshVijayK/HyperV-Installer/main/HyperV-Installer.ps1
   ```
4. Share the one-liner with users!

---

## ⚠️ Disclaimer

- This is **unofficial** — Microsoft does not support Hyper-V on Windows Home
- Works on most Windows 10/11 Home systems but may not work on all
- Always have a system backup before running system-level scripts
- Use at your own risk

---

**Developer:** Vignesh Vijay K  
**GitHub:** https://github.com/VigneshVijayK
