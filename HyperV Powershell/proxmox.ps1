[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

#$servername = Read-Host -Prompt 'What is the server IP?'
$servername = "209.208.48.68"

#$uri = 'https://'+$servername+':8006/api2/json/'
$uri = 'https://209.208.48.68:8006/api2/json/'

$ticketuri = $uri+'access/ticket'
#$C = Get-Credential -Message 'Enter the server login'

#==========Authenticate with the Server===========
#$ticket = Invoke-RestMethod -Method Post -uri $ticketuri -body ('username='+$C.UserName+'@pam&password='+$C.GetNetworkCredential().Password) -Verbose
#$ticket = Invoke-WebRequest -Method Post -uri $ticketuri -Credential $C -Verbose
$ticket = Invoke-RestMethod -Method Post -uri $ticketuri -body ('username=root@pam&password=Nrprocks!') -Verbose

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$cookie = New-Object System.Net.Cookie    
$cookie.Name = "PVEAuthCookie"
$cookie.Value = $ticket.data.ticket
$cookie.Domain = $servername
$session.Cookies.Add($cookie);
#=================================================

#region ::: Variables
$TotalHddMax = 0.00
$TotalHddCurrent = 0.00
$TotalHddOnline = 0.00
$TotalRamMax = 0.00
$TotalRamCurrent = 0.00
$TotalRamOnline = 0.00
$driveArrCurrent = New-Object 'System.Collections.Generic.Dictionary[string,double]'
$driveArrOnline = New-Object 'System.Collections.Generic.Dictionary[string,double]'
$driveArrMax = New-Object 'System.Collections.Generic.Dictionary[string,double]'
$driveArrUsed = @{}
$driveArrFree = @{}
$hddContainer = "info"
$hddUsedProgressBar = "success"
$vhd_usedPB = ""
$vhd_table = ""
$vms_string = ""
$hddMaxPercent = 0.00
$hddOnlinePercent = 0.00
$hddCurrentPercent = 0.00
$harddriveString = ""

$reportTitle = "Proxmox Report for $($nodes.data[0].node)"
$reportDate = "$(Get-Date -Format "MM-dd-yyyy")"

$nodes = Invoke-RestMethod -uri ($uri+'nodes/') -WebSession $session -Verbose
foreach ($node in $nodes.data) {
    $qemus = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/qemu') -WebSession $session -Verbose
    $lxcs = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/lxc') -WebSession $session -Verbose
    $storages = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/storage') -WebSession $session -Verbose
    foreach ($storage in $storages.data) {
        $content = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/storage/'+$storage.storage+'/content') -WebSession $session -Verbose
    }
}

$HostMemory = $nodes.data | Select maxmem
$HostProcessors = $nodes.data | Select maxcpu
$Disks = $content.data | Where content -eq "images" | Select vmid, size, used | Sort vmid
$Storages = $storages.data | Select storage, total, used, avail #$driveLetters = gdr -PSProvider 'FileSystem' | Select Name, Used, Free 

$VMs = $qemus.data | Select vmid, name, status, mem, maxmem, cpus | Sort vmid
$LXCs = $lxcs.data | Select vmid, name, status, mem, maxmem, cpus | Sort vmid
#<-----VMs---------->
$runningVMs = ($VMs | Where status -eq "running" | Measure).Count
$pausedVMs = ($VMs | Where {($_.status -eq "paused") -or ($_.status -eq "saved")} | Measure).Count
$offlineVMs = ($VMs | Where status -eq "stopped" | Measure).Count
$totalVMs = ($VMs).Count
#<-----Containers--->
$runningLXCs = ($LXCs | Where status -eq "running" | Measure).Count
$pausedLXCs = ($LXCs | Where {($_.status -eq "paused") -or ($_.status -eq "saved")} | Measure).Count
$offlineLXCs = ($LXCs | Where status -eq "stopped" | Measure).Count
$totalLXCs = ($LXCs).Count

#endregion ::: Variables

#foreach ($node in $nodes.data) {
#    $qemus = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/qemu') -WebSession $session -Verbose
#    foreach ($qemu in $qemus.data) {
#        #will need to populate the {storage} name since it won't always be local
#        $content = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/storage/local/content') -WebSession $session -Verbose
#        foreach ($item in $content.data) {
#            if ($item.content -eq "images") {
#                if($item.vmid -eq $qemu.vmid)
#                {
#                    $disk = $item
#                    $disk
#                }
#            }
#        }
#    }
#}
    
#$test = Invoke-RestMethod -uri ($uri+'nodes/') -WebSession $session
#$test.data

$storages

Remove-Variable session