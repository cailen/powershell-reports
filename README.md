# powershell-reports
Generates PDF Reports from Proxmox and Hyper-V

These Powershell scripts are meant to help automate the strenuous task of tallying resources for virtualization hosts,
showing current and total utilization charts in an easily-viewable PDF format.

Note: In order for this to work, you will need the following:

## Hyper-V:
- Administrator Powershell on the virtualization host you intend to generate the report on.
- Permission to run scripts (you can also copy and paste this, just make sure to have word wrap off before copying it into ISE or PS)
- pdflayer.com API key. ** You must add the API key to the script toward the bottom or it will not work. **
## Proxmox:
- Administrator Powershell on any Windows computer that has access to the destination server.
- This, by default, uses port 8600. It can be changed.
- Permission to run scripts (you can also copy and paste this, just make sure to have word wrap off before copying it into ISE or PS)
- pdflayer.com API key. ** You must add the API key to the script toward the bottom or it will not work. **

Let me know if you have any issues!
@cailen
