PRO X 2 LIGHTSPEED - Dolby Atmos for Headphones fix
====================================================
Problem: Logitech's driver declares the headset as a 7.1 speaker (8ch format + HX2E surround APO +
logi_audio_surround upper filter). Windows hides headphone spatial sound / Dolby Atmos on 7.1 endpoints.

Fix: registry-only. Sets the endpoint to stereo, removes the HX2E APO and the upper filter.
The Logitech driver and G HUB stay installed. A SYSTEM scheduled task ("AtmosFix") re-applies it at
startup/logon because the driver rewrites the settings.

Use:
 1. Install Dolby Access (Microsoft Store) and plug in the headset.
 2. Double-click Enable-Atmos.bat (accepts the UAC prompt). Reboot if Atmos doesn't show up.
 3. Settings > Sound > PRO X 2 > Spatial sound > Dolby Atmos for Headphones.
Undo: double-click Restore-Logitech.bat, then reboot.
Preview only: powershell -File atmos-fix.ps1 -Check

Notes: backups go to C:\ProgramData\AtmosFix\backup. Temporarily takes ownership of 3-5 registry keys and
restores their original permissions. G HUB's own 7.1 surround is disabled (Atmos replaces it).
Tested on Windows 10 22H2 only. Use at your own risk; read the script first.

Disclaimer
----------
This is an unofficial community tool. It is not affiliated with, endorsed by, or supported by Logitech or
Dolby. "Logitech", "PRO X 2 LIGHTSPEED" and "Dolby Atmos" are trademarks of their respective owners and are
used only to describe compatibility. It modifies Windows registry settings; doing so may affect your device
support or warranty. Provided "AS IS" under the MIT license (see LICENSE), with no warranty. Back up first
and use at your own risk.
