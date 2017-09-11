add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    
    public class IDontCarePolicy : ICertificatePolicy {
        public IDontCarePolicy() {}
        public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate cert,
            WebRequest wRequest, int certProb) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy 

$servername = Read-Host -Prompt 'What is the server IP?'
$uri = 'https://' + $servername + ':8006/api2/json/'
$ticketuri = $uri + 'access/ticket'
$C = Get-Credential -Message 'Enter the server login'
$passwd = [uri]::EscapeDataString($C.GetNetworkCredential().Password)
#==========Authenticate with the Server===========
$ticket = Invoke-RestMethod -Method Post -uri $ticketuri -body ('username=' + $C.UserName + '@pam&password=' + $passwd) -SessionVariable session -Verbose
$cookie = New-Object System.Net.Cookie    
$cookie.Name = "PVEAuthCookie"
$cookie.Value = $ticket.data.ticket
$cookie.Domain = $servername
$session.Cookies.Add($cookie);
#=================================================

Invoke-RestMethod -uri ($uri + 'nodes/') -WebSession $session -Verbose

$nodes = Invoke-RestMethod -uri ($uri + 'nodes/') -WebSession $session -Verbose
#This foreach will probably need to go beyond beyond everything to work for multiple nodes
foreach ($node in $nodes.data) {
    if ($node.uptime) {
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
        $lxcs_string = ""
        $hddMaxPercent = 0.00
        $hddOnlinePercent = 0.00
        $hddCurrentPercent = 0.00
        $harddriveString = ""

        $qemus = Invoke-RestMethod -uri ($uri + 'nodes/' + $node.node + '/qemu') -WebSession $session -Verbose
        $lxcs = Invoke-RestMethod -uri ($uri + 'nodes/' + $node.node + '/lxc') -WebSession $session -Verbose
        $storages = Invoke-RestMethod -uri ($uri + 'nodes/' + $node.node + '/storage') -WebSession $session -Verbose

        foreach ($storage in $storages.data) {
            $tempcontent = Invoke-RestMethod -uri ($uri + 'nodes/' + $node.node + '/storage/' + $storage.storage + '/content') -WebSession $session -Verbose
            $content = $content + $tempcontent.data
        }

        $reportTitle = "Private Cloud Report for $($node.node)"
        $reportDate = "$(Get-Date -Format "MM-dd-yyyy")"

        $HostMemory = $node | Select-Object maxmem
        $HostMemory
        $HostProcessors = $node | Select-Object maxcpu
        $VHDs = $content | Where-Object content -eq "images" | Select-Object vmid, size, used, volid | Sort-Object vmid
        $Storages = $storages.data | Select-Object storage, total, used, avail #$driveLetters = gdr -PSProvider 'FileSystem' | Select Name, Used, Free 

        $VMs = $qemus.data | Select-Object vmid, name, status, mem, maxmem, cpus | Sort-Object vmid
        $LXCs = $lxcs.data | Select-Object vmid, name, status, mem, maxmem, cpus | Sort-Object vmid
        #<-----VMs---------->
        $runningVMs = ($VMs | Where-Object status -eq "running" | Measure-Object).Count
        $pausedVMs = ($VMs | Where-Object {($_.status -eq "paused") -or ($_.status -eq "saved")} | Measure-Object).Count
        $offlineVMs = ($VMs | Where-Object status -eq "stopped" | Measure-Object).Count
        $totalVMs = ($VMs).Count
        #<-----Containers--->
        $runningLXCs = ($LXCs | Where-Object status -eq "running" | Measure-Object).Count
        $pausedLXCs = ($LXCs | Where-Object {($_.status -eq "paused") -or ($_.status -eq "saved")} | Measure-Object).Count
        $offlineLXCs = ($LXCs | Where-Object status -eq "stopped" | Measure-Object).Count
        $totalLXCs = ($LXCs).Count

        #region ::: Get the memory and hard drive stats from the VMs
        Foreach ($VM in $VMs) {
            $TotalRamMax += $VM.maxmem
            $TotalRamCurrent += $VM.mem
    
            if ($VM.status -eq "running") {
                $TotalRamOnline += $VM.maxmem
            }

            #$VHDs = $VM | Get-VMHardDiskDrive | Get-VHD | Select Path, FileSize, Size

            #Fill the drive stats dictionary (Key=Drive Letter, Value=Size)
            foreach ($VHD in ($VHDs | Where-Object vmid -eq $VM.vmid)) {
                #This splits off the name of the storage from the actual disk file name
                $drivePath = $VHD.volid.Split(':')[0]
                $driveArrCurrent[$drivePath] += 0.0
                $driveArrOnline[$drivePath] += 0.0

                if ($VM.status -eq "running") {
                    if ($driveArrMax.ContainsKey($drivePath)) {
                        $driveArrMax[$drivePath] += $VHD.size -as [float]
                        $driveArrCurrent[$drivePath] += $VHD.used
                        $driveArrOnline[$drivePath] += $VHD.size
                    }
                    else {
                        $driveArrMax[$drivePath] += $VHD.size -as [float]
                        $driveArrCurrent[$drivePath] += $VHD.used -as [float]
                        $driveArrOnline[$drivePath] += $VHD.size -as [float]
                        $driveArrFree.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object avail))
                        $driveArrUsed.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object used))
                    }
                }
                else {
                    if ($driveArrMax.ContainsKey($drivePath)) {
                        $driveArrMax[$drivePath] += $VHD.size
                    }
                    else {
                        $driveArrMax[$drivePath] += $VHD.size
                        $driveArrFree.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object avail))
                        $driveArrUsed.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object used))
                    }
                }
            }
        }
        #endregion ::: Get the memory and hard drive stats from the VMs

        #region ::: Get the memory and hard drive stats from the LXCs
        Foreach ($LXC in $LXCs) {
            $TotalRamMax += $LXC.maxmem
            $TotalRamCurrent += $LXC.mem
    
            if ($LXC.status -eq "running") {
                $TotalRamOnline += $LXC.maxmem
            }

            #$VHDs = $VM | Get-VMHardDiskDrive | Get-VHD | Select Path, FileSize, Size

            #Fill the drive stats dictionary (Key=Drive Letter, Value=Size)
            foreach ($VHD in ($VHDs | Where-Object vmid -eq $LXC.vmid)) {
                #This splits off the name of the storage from the actual disk file name
                $drivePath = $VHD.volid.Split(':')[0]
                $driveArrCurrent[$drivePath] += 0.0
                $driveArrOnline[$drivePath] += 0.0

                if ($LXC.status -eq "running") {
                    if ($driveArrMax.ContainsKey($drivePath)) {
                        $driveArrMax[$drivePath] += $VHD.size -as [float]
                        $driveArrCurrent[$drivePath] += $VHD.used
                        $driveArrOnline[$drivePath] += $VHD.size
                    }
                    else {
                        $driveArrMax[$drivePath] += $VHD.size -as [float]
                        $driveArrCurrent[$drivePath] += $VHD.used -as [float]
                        $driveArrOnline[$drivePath] += $VHD.size -as [float]
                        $driveArrFree.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object avail))
                        $driveArrUsed.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object used))
                    }
                }
                else {
                    if ($driveArrMax.ContainsKey($drivePath)) {
                        $driveArrMax[$drivePath] += $VHD.size
                    }
                    else {
                        $driveArrMax[$drivePath] += $VHD.size
                        $driveArrFree.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object avail))
                        $driveArrUsed.Add($drivePath, ($Storages | Where-Object storage -ieq $drivePath | Select-Object used))
                    }
                }
            }
        }
        #endregion ::: Get the memory and hard drive stats from the LXCs

        #region ::: HDD Progress Bar Calculations
        #=============================

        #Go through each drive
        foreach ($driveFor in $driveArrMax.GetEnumerator()) {
            $HostDriveTotal = ([float]$driveArrFree[$driveFor.Key].avail) + ([float]$driveArrUsed[$driveFor.Key].used)

            #find out the percentages
            [float]$hddMaxPercent = ("{0:N2}" -f ((($driveArrMax.Get_Item($driveFor.Key)) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))
            [float]$hddUsedPercent = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].used) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))
    
            if ($driveArrOnline.Count -gt 0) {
                [float]$hddOnlinePercent = ("{0:N2}" -f ((($driveArrOnline.Get_Item($driveFor.Key)) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))
            }
            else {
                $hddOnlinePercent = 0.0
            }
    
            if ($driveArrCurrent.Count -gt 0) {
                [float]$hddCurrentPercent = ("{0:N2}" -f ((($driveArrCurrent.Get_Item($driveFor.Key)) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))
            }
            else {
                $hddCurrentPercent = 0.0
            }
            #region ::: setup the progress bar percentages (in other words, if they're over 100%, set them to 100%
            switch ($hddUsedPercent) {
                {$hddUsedPercent -gt 90.00} {$hddUsedProgressBar = "danger"; break}
                {$hddUsedPercent -gt 75.00} {$hddUsedProgressBar = "warning"; break}
                default {$hddUsedProgressBar = "success"}
            }

            if ($hddMaxPercent -gt 100) {$hddMaxPercent = 100.00; }
            if ($hddCurrentPercent -gt 100) {
                $hddCurrentPercent = 100.00 
                $hddGlyph = '<span class="glyphicon glyphicon-remove" style="color:#E53935"/>'
            }
            if ($hddOnlinePercent -ge 100) {
                $hddOnlinePercent = 100.00
                $hddGlyph = '<span class="glyphicon glyphicon-remove" style="color:#E53935"/>'
            }

            switch ($hddOnlinePercent) {
                {$hddOnlinePercent -gt 90.00} {$hddContainer = "danger"; $hddGlyph = '<span class="glyphicon glyphicon-remove" style="color:#E53935"/>'; break}
                {$hddOnlinePercent -gt 75.00} {$hddContainer = "warning"; $hddGlyph = '<span class="glyphicon glyphicon-exclamation-sign" style="color:#FFA726"/>'; break}
                default {$hddContainer = "success"; $hddGlyph = '<span class="glyphicon glyphicon-ok" style="color:#66BB6A"/>'; break}
            }

            $hddMaxProgressBar = "danger"
            $hddOnlineProgressBar = "success"
            $hddCurrentProgressBar = "info"

            switch ($hddOnlinePercent) {
                {$hddOnlinePercent -gt 90.00} {$hddOnlineProgressBar = "danger"; break}
                {$hddOnlinePercent -gt 75.00} {$hddOnlineProgressBar = "warning"; break}
                default {$hddOnlineProgressBar = "success"}
            }
            switch ($hddCurrentPercent) {
                {$hddCurrentPercent -gt 90.00} {$hddCurrentProgressBar = "danger"; break}
                {$hddCurrentPercent -gt 75.00} {$hddCurrentProgressBar = "warning"; break}
                default {$hddCurrentProgressBar = "info"}
            }
            #endregion ::: setup the progress bar percentages (in other words, if they're over 100%, set them to 100%

            #region ::: adjust the percentages for the progress bar
            #IF ONLINE IS BIGGER THAN MAX, MAX IS GOING TO BE 0
            if ($hddOnlinePercent -ge $hddMaxPercent) {
                #IF CURRENT IS BIGGER THAN ONLINE, BOTH MAX AND ONLINE ARE 0
                if ($hddCurrentPercent -ge $hddOnlinePercent) {    
                    $hddOnlinePercent = 0
                    $hddMaxPercent = 0
                }
                #IF ONLINE IS BIGGER THAN CURRENT, CURRENT STAYS THE SAME AND ONLINE IS THE REMAINDER
                else {
                    $hddOnlinePercent = ($hddOnlinePercent - $hddCurrentPercent)
                    $hddMaxPercent = 0
                }
            }
            #IF MAX IS BIGGER THAN ONLINE, MAX IS THE REMAINDER
            elseif ($hddMaxPercent -ge $hddOnlinePercent) {
                #IF MAX IS BIGGER THAN CURRENT, MAX and ONLINE ARE REMAINDERS
                if ($hddMaxPercent -ge $hddCurrentPercent) {
                    $hddOnlinePercent = ($hddOnlinePercent - $hddCurrentPercent)
                    $hddMaxPercent = ($hddMaxPercent - ($hddOnlinePercent + $hddCurrentPercent))
                }
                #IF CURRENT IS BIGGER THAN MAX, MAX IS 0 AND ONLINE IS THE REMAINDER
                else {  
                    $hddOnlinePercent = ($hddOnlinePercent - $hddCurrentPercent)
                    $hddMaxPercent = 0
                }
            }
    
            # if($hddCurrentPercent -ge $hddOnlinePercent)
            # Since current usage is higher than other metrics, the rest are set to 0
            else {
                $hddOnlinePercent = 0
                $hddMaxPercent = 0
            }
            #endregion ::: adjust the percentages for the progress bar

            #String for the Hard Drives Summary
            $harddriveString += @"
			<div class="row">
                            <div class="col-xs-12 col-md-12">
                                <h4 class="vmname"><span class="glyphicon glyphicon-hdd"></span> $($driveFor.Key) $hddGlyph</h4>
                                <div class="row">
                                    <div class="col-xs-6 col-md-6">
                                        <table class="table table-striped table-condensed text-center">
                                            <tr>
                                                <th>Current Use</th>
                                                <th>Running Max</th>
                                                <th>Total Max</th>
                                                <th>System Capacity</th>
                                            </tr>
                                            <tr>
                                                <td>$("{0:N2}" -f (($driveArrCurrent.Get_Item($driveFor.Key))/1gb -as [float]))</td>
                                                <td>$("{0:N2}" -f (($driveArrOnline.Get_Item($driveFor.Key))/1gb -as [float]))</td>
                                                <td>$("{0:N2}" -f (($driveArrMax.Get_Item($driveFor.Key))/1gb -as [float]))</td>
                                                <td>$("{0:N2} GB" -f ($HostDriveTotal/1gb -as [float]))</td>
                                            </tr>
                                        </table>
                                        <div class="progress">
                                            <div class="progress-bar progress-bar-$hddCurrentProgressBar active"
                                                aria-valuenow="$hddCurrentPercent" aria-valuemin="0" 
                                                aria-valuemax="100" style="width:$hddCurrentPercent%">
                                                <span>Current</span>
                                            </div>
                                            <div class="progress-bar progress-bar-$hddOnlineProgressBar" 
                                                aria-valuenow="$hddOnlinePercent" aria-valuemin="0" 
                                                aria-valuemax="100" style="width:$hddOnlinePercent%">
                                                <span>Online</span>
                                            </div>
                                            <div class="progress-bar progress-bar-$hddMaxProgressBar" 
                                                aria-valuenow="$hddMaxPercent" aria-valuemin="0" 
                                                aria-valuemax="100" style="width:$hddMaxPercent%">
                                                <span>Total</span>
                                            </div>
                                        </div>
                                    </div>
                                    <div class="col-xs-6 col-md-6">
                                        <table class="table table-striped table-condensed text-center">
                                            <tr>
                                                <th>Drive Used Space</th>
                                                <th>Drive Free Space</th>
                                                <th>System Capacity</th>
                                            </tr>
                                            <tr>
                                                <td>$("{0:N2}" -f (($driveArrUsed[$driveFor.Key].Used)/1gb -as [float]))</td>
                                                <td>$("{0:N2}" -f (($driveArrFree[$driveFor.Key].avail)/1gb -as [float]))</td>
                                                <td>$("{0:N2} GB" -f ($HostDriveTotal/1gb -as [float]))</td>
                                            </tr>
                                        </table>
                                        <div class="progress">
                                            <div class="progress-bar progress-bar-$hddUsedProgressBar active"
                                                aria-valuenow="$hddUsedPercent" aria-valuemin="0" 
                                                aria-valuemax="100" style="width:$hddUsedPercent%">
                                                <span>$hddUsedPercent%</span>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
			</div>
"@
        }

        #=====================
        #endregion ::: HDD Calculations

        #region ::: RAM Progress Bar Calculations
        #=============================

        [float]$ramMaxPercent = ("{0:N2}" -f (($TotalRamMax / 1gb -as [float]) / ($HostMemory.maxmem / 1gb -as [float]) * 100))
        [float]$ramOnlinePercent = ("{0:N2}" -f (($TotalRamOnline / 1gb -as [float]) / ($HostMemory.maxmem / 1gb -as [float]) * 100))
        [float]$ramCurrentPercent = ("{0:N2}" -f (($TotalRamCurrent / 1gb -as [float]) / ($HostMemory.maxmem / 1gb -as [float]) * 100))

        if ($ramMaxPercent -gt 100) {$ramMaxPercent = 100}
        if ($ramCurrentPercent -gt 100) {$ramCurrentPercent = 100}
        if ($ramOnlinePercent -gt 100) {$ramOnlinePercent = 100}   

        $memoryMaxProgressBar = "danger"
        $memoryOnlineProgressBar = "success"
        $memoryCurrentProgressBar = "info"

        switch ($ramOnlinePercent) {
            {$_ -gt 90.00} {$memoryOnlineProgressBar = "danger"; break}
            {$_ -gt 75.00} {$memoryOnlineProgressBar = "warning"; break}
            default {$memoryOnlineProgressBar = "success"}
        }
        switch ($ramCurrentPercent) {
            {$_ -gt 90.00} {$memoryCurrentProgressBar = "danger"; break}
            {$_ -gt 75.00} {$memoryCurrentProgressBar = "warning"; break}
            default {$memoryCurrentProgressBar = "info"}
        }

        #region ::: Adjust the percentages for the progress bar
        #IF ONLINE IS BIGGER THAN MAX, MAX IS GOING TO BE 0
        if ($ramOnlinePercent -ge $ramMaxPercent) {
            #IF CURRENT IS BIGGER THAN ONLINE, BOTH MAX AND ONLINE ARE 0
            if ($ramCurrentPercent -ge $ramOnlinePercent) {    
                $ramOnlinePercent = 0
                $ramMaxPercent = 0
            }
            #IF ONLINE IS BIGGER THAN CURRENT, CURRENT STAYS THE SAME AND ONLINE IS THE REMAINDER
            else {
                $ramOnlinePercent = ($ramOnlinePercent - $ramCurrentPercent)
                $ramMaxPercent = 0
            }
        }
        #IF MAX IS BIGGER THAN ONLINE, MAX IS THE REMAINDER
        elseif ($ramMaxPercent -ge $ramOnlinePercent) {
            #IF MAX IS BIGGER THAN CURRENT, MAX and ONLINE ARE REMAINDERS
            if ($ramMaxPercent -ge $ramCurrentPercent) {
                $ramOnlinePercent = ($ramOnlinePercent - $ramCurrentPercent)
                $ramMaxPercent = ($ramMaxPercent - ($ramOnlinePercent + $ramCurrentPercent))
            }
            #IF CURRENT IS BIGGER THAN MAX, MAX IS 0 AND ONLINE IS THE REMAINDER
            else {  
                $ramOnlinePercent = ($ramOnlinePercent - $ramCurrentPercent)
                $ramMaxPercent = 0
            }
        }
        else {
            # if($ramCurrentPercent -ge $ramOnlinePercent)
            # Since current usage is higher than other metrics, the rest are set to 0 {
            $ramOnlinePercent = 0
            $ramMaxPercent = 0
        }
        #endregion ::: Adjust the percentages for the progress bar
        #=====================
        #endregion ::: RAM Calculations

        #region ::: VMs
        #Create the individual VM panels
        Foreach ($VM in $VMs) {
            $VM_style = ""
            $VM_state = ""

            [float]$VHD_Used = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].avail) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))

            $(Switch ($VM.status) {
                    "running" {$VM_style = "success"; $VM_state = '<span class="glyphicon glyphicon-play" style="font-size:1.6em;"></span>'; break; }
                    "paused" {$VM_style = "warning"; $VM_state = '<span class="glyphicon glyphicon-pause" style="font-size:1.6em;"></span>'; break; }
                    "stopped" {$VM_style = "danger"; $VM_state = '<span class="glyphicon glyphicon-stop" style="font-size:1.6em;"></span>'; break; }
                    "saved" {$VM_style = "warning"; $VM_state = '<span class="glyphicon glyphicon-save" style="font-size:1.6em;"></span>'; break; }
                    default {$VM_style = "info"; $VM_state = '<span class="glyphicon glyphicon-asterisk" style="font-size:1.6em;"></span>'; break; }
                })

            foreach ($VHD in ($VHDs | Where-Object vmid -eq $VM.vmid)) {
                $VHD_temp = $VHD
                [float]$vhd_UsedPercent = ("{0:N2}" -f ($VHD_temp.used / 1gb –as [float]) / ($VHD_temp.size / 1gb –as [float]) * 100)

                switch ($vhd_UsedPercent) {
                    {$vhd_UsedPercent -gt 90.00} {$vhd_ProgressBar = "danger"; break}
                    {$vhd_UsedPercent -gt 75.00} {$vhd_ProgressBar = "warning"; break}
                    default {$vhd_ProgressBar = "success"}
                }

                $vhd_table += @"
            <tr>
                <td>$($VHD.volid.Split(':')[0])</td>
                <td>$("{0:N2} GB" -f ($VHD_temp.used/1gb –as [float]))</td>
                <td>$("{0:N2} GB" -f ($VHD_temp.size/1gb –as [float]))</td>
                <td>
                    <div class="progress">
                        <div class="progress-bar progress-bar-$vhd_ProgressBar" 
                            aria-valuenow="$vhd_UsedPercent" aria-valuemin="0" 
                            aria-valuemax="100" style="width:$vhd_UsedPercent%">
                            <span>$("{0:N0}" -f ($vhd_UsedPercent))%</span>
                        </div>
                    </div>
                </td>
            </tr>
"@
            }

            $vms_string += @"
	<div class="row text-center">
		<div class="col-xs-3">
			<div class="panel panel-$VM_style">
				<div class="panel-heading" style="margin-bottom:5px;">
					<h4 class="h4">$($VM.name)</h4>
					<span class="badge">$($VM.cpus) vCPU</span>
					$VM_state
				</div>
			</div>
		</div>
		<div class="col-xs-3">
			<h4 class="text-center">$("{0:N2}" -f ($VM.mem/1gb -as [float])) of $("{0:N2} GB" -f ($VM.maxmem/1gb -as [float]))</h4>
			<div class="progress">
                <div class="progress-bar progress-bar-primary" role="progressbar" 
                    aria-valuenow="$("{0:N2}" -f (($VM.mem/1gb -as [float])/($VM.maxmem/1gb -as [float]) * 100))" aria-valuemin="0" aria-valuemax="100" style="width:$("{0:N2}" -f (($VM.mem/1gb -as [float])/($VM.maxmem/1gb -as [float]) * 100))%">
                </div>
            </div>
		</div>
		<div class="col-xs-6">
			<table class="table table-striped table-condensed text-center" style="margin-bottom:2px;">
                <thead>
                    <tr>
                        <th>Loc</th>
                        <th>Current Size</th>
                        <th>Max Size</th>
                        <th>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
                    </tr>
                </thead>
                <tbody>
                    $vhd_table
                </tbody>
            </table>
		</div>
	</div>
"@

            #Clear the VHD string variables
            $vhd_table = ""
            $vhd_usedPB = ""
        }
        #endregion ::: VMs

        #region ::: LXCs
        #Create the individual LXC panels
        Foreach ($LXC in $LXCs) {
            $VM_style = ""
            $VM_state = ""

            [float]$VHD_Used = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].avail) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))

            $(Switch ($LXC.status) {
                    "running" {$VM_style = "success"; $VM_state = '<span class="glyphicon glyphicon-play" style="font-size:1.6em;"></span>'; break; }
                    "paused" {$VM_style = "warning"; $VM_state = '<span class="glyphicon glyphicon-pause" style="font-size:1.6em;"></span>'; break; }
                    "stopped" {$VM_style = "danger"; $VM_state = '<span class="glyphicon glyphicon-stop" style="font-size:1.6em;"></span>'; break; }
                    "saved" {$VM_style = "warning"; $VM_state = '<span class="glyphicon glyphicon-save" style="font-size:1.6em;"></span>'; break; }
                    default {$VM_style = "info"; $VM_state = '<span class="glyphicon glyphicon-asterisk" style="font-size:1.6em;"></span>'; break; }
                })

            foreach ($VHD in ($VHDs | Where-Object vmid -eq $LXC.vmid)) {
                $VHD_temp = $VHD
                [float]$vhd_UsedPercent = ("{0:N2}" -f ($VHD_temp.used / 1gb –as [float]) / ($VHD_temp.size / 1gb –as [float]) * 100)

                switch ($vhd_UsedPercent) {
                    {$vhd_UsedPercent -gt 90.00} {$vhd_ProgressBar = "danger"; break}
                    {$vhd_UsedPercent -gt 75.00} {$vhd_ProgressBar = "warning"; break}
                    default {$vhd_ProgressBar = "success"}
                }

                $vhd_table += @"
            <tr>
                <td>$($VHD.volid.Split(':')[0])</td>
                <td>$("{0:N2} GB" -f ($VHD_temp.used/1gb –as [float]))</td>
                <td>$("{0:N2} GB" -f ($VHD_temp.size/1gb –as [float]))</td>
                <td>
                    <div class="progress">
                        <div class="progress-bar progress-bar-$vhd_ProgressBar" 
                            aria-valuenow="$vhd_UsedPercent" aria-valuemin="0" 
                            aria-valuemax="100" style="width:$vhd_UsedPercent%">
                            <span>$("{0:N0}" -f ($vhd_UsedPercent))%</span>
                        </div>
                    </div>
                </td>
            </tr>
"@
            }

            $lxcs_string += @"
	<div class="row text-center">
		<div class="col-xs-3">
			<div class="panel panel-$VM_style">
				<div class="panel-heading" style="margin-bottom:5px;">
					<h4 class="h4">$($LXC.name)</h4>
					<span class="badge">$($LXC.cpus) vCPU</span>
					$VM_state
				</div>
			</div>
		</div>
		<div class="col-xs-3">
			<h4 class="text-center">$("{0:N2}" -f ($LXC.mem/1gb -as [float])) of $("{0:N2} GB" -f ($LXC.maxmem/1gb -as [float]))</h4>
			<div class="progress">
                <div class="progress-bar progress-bar-primary" role="progressbar" 
                    aria-valuenow="$("{0:N2}" -f (($LXC.mem/1gb -as [float])/($LXC.maxmem/1gb -as [float]) * 100))" aria-valuemin="0" aria-valuemax="100" style="width:$("{0:N2}" -f (($LXC.mem/1gb -as [float])/($LXC.maxmem/1gb -as [float]) * 100))%">
                </div>
            </div>
		</div>
		<div class="col-xs-6">
			<table class="table table-striped table-condensed text-center" style="margin-bottom:2px;">
                <thead>
                    <tr>
                        <th>Loc</th>
                        <th>Current Size</th>
                        <th>Max Size</th>
                        <th>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>
                    </tr>
                </thead>
                <tbody>
                    $vhd_table
                </tbody>
            </table>
		</div>
	</div>
"@

            #Clear the VHD string variables
            $vhd_table = ""
            $vhd_usedPB = ""
        }
        #endregion ::: LXCs

        #region ::: HEADER HTML
        $header = 
        @"
<title>$reportTitle on $reportDate</title>
<link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css" integrity="sha384-1q8mTJOASx8j1Au+a5WDVnPi2lkFfwwEAa8hDDdjZlpLegxhjVME1fgjWPGmkzs7" crossorigin="anonymous">
    <link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap-theme.min.css" integrity="sha384-fLW2N01lMqjakBkx3l/M9EahuwpSfeNvV63J5ezn3uZzapT0u7EYsXMjQV+0En5r" crossorigin="anonymous">
    <style type="text/css">
		svg {
			fill: #fff;
		}

        .vmname {
            text-transform: uppercase;
            text-align: center;
            padding-bottom: 2px;
        }
        
        .row {
            display: -webkit-box;
            display: -webkit-flex;
            display: -ms-flexbox;
            display: flex;
            flex-wrap: wrap;
        }
        
        .row> [class*='col-'] {
            display: flex;
            flex-direction: column;
        }
        
        th {
            text-align: center;
        }
        
        table .progress {
            margin-bottom: 0;
        }
        
        .btn-primary {
            background: #0079c6;
            color: #ffffff;
            border: 0;
        }
        
        .btn-success {
            background: #77D843;
            color: #ffffff;
            border: 0;
        }
        
        .btn-danger {
            background: #E53935;
            color: #ffffff;
            border: 0;
        }
        
        .btn-warning {
            background: #FFA000;
            color: #ffffff;
            border: 0;
        }
        
        .btn-info {
            background: #0079c6;
            color: #ffffff;
            border: 0;
        }
        
        .panel {
            border: 0;
            box-shadow: 0 4px 5px 0 rgba(0, 0, 0, .14), 0 1px 10px 0 rgba(0, 0, 0, .12), 0 2px 4px -1px rgba(0, 0, 0, .2);
            background: DADFE1
        }
        
        .panel-success> .panel-heading {
            background: #77D843;
            color: #ffffff;
            border: 0;
        }
        
        .panel-primary> .panel-heading {
            background: #0079c6;
            color: #ffffff;
            border: 0;
        }
        
        .panel-warning> .panel-heading {
            background: #FFA000;
            color: #ffffff;
            border: 0;
        }
        
        .panel-danger> .panel-heading {
            background: #E53935;
            color: #ffffff;
            border: 0;
        }
        
        .panel-info> .panel-heading {
            background: #0079c6;
            color: #ffffff;
        }
        
        body {
            background: #263746;
        }
        
        .progress {
            background: #778692;
        }
        
        .progress> .progress-bar-primary {
            background: #0079c6;
        }

        .progress> .progress-bar-primary {
            background: #77D843;
        }

        /* Print styling */
        
        @media print {
            [class*="col-sm-"] {
                float: left;
            }
            [class*="col-xs-"] {
                float: left;
            }
            .col-sm-12,
            .col-xs-12 {
                width: 100% !important;
            }
            .col-sm-11,
            .col-xs-11 {
                width: 91.66666667% !important;
            }
            .col-sm-10,
            .col-xs-10 {
                width: 83.33333333% !important;
            }
            .col-sm-9,
            .col-xs-9 {
                width: 75% !important;
            }
            .col-sm-8,
            .col-xs-8 {
                width: 66.66666667% !important;
            }
            .col-sm-7,
            .col-xs-7 {
                width: 58.33333333% !important;
            }
            .col-sm-6,
            .col-xs-6 {
                width: 50% !important;
            }
            .col-sm-5,
            .col-xs-5 {
                width: 41.66666667% !important;
            }
            .col-sm-4,
            .col-xs-4 {
                width: 33.33333333% !important;
            }
            .col-sm-3,
            .col-xs-3 {
                width: 25% !important;
            }
            .col-sm-2,
            .col-xs-2 {
                width: 16.66666667% !important;
            }
            .col-sm-1,
            .col-xs-1 {
                width: 8.33333333% !important;
            }
            .col-sm-1,
            .col-sm-2,
            .col-sm-3,
            .col-sm-4,
            .col-sm-5,
            .col-sm-6,
            .col-sm-7,
            .col-sm-8,
            .col-sm-9,
            .col-sm-10,
            .col-sm-11,
            .col-sm-12,
            .col-xs-1,
            .col-xs-2,
            .col-xs-3,
            .col-xs-4,
            .col-xs-5,
            .col-xs-6,
            .col-xs-7,
            .col-xs-8,
            .col-xs-9,
            .col-xs-10,
            .col-xs-11,
            .col-xs-12 {
                float: left !important;
            }

			.panel {
				margin: 20px;
				}
            body {
                margin: 0;
                padding 0 !important;
                min-width: 768px;
				background: #263746;
            }
            .container {
                width: auto;
                min-width: 750px;
				background: #fff;
            }
            body {
                font-size: 10px;
            }
            a[href]:after {
                content: none;
            }
            .noprint,
            div.alert,
            header,
            .group-media,
            .btn,
            .footer,
            form,
            #comments,
            .nav,
            ul.links.list-inline,
            ul.action-links {
                display: none !important;
            }
        }
</style>
"@
        #endregion ::: HEADER HTML

        #region ::: BODY HTML
        $body = 
        @"
    <div class="container" style="padding-top: 5px;">
        <div class="jumbotron text-center" style="background-color: #0079c6; color:white; height:400px; padding-top:10px; padding-bottom:10px; margin-bottom:20px;">
			<svg xmlns="http://www.w3.org/2000/svg" height="100" width="200" viewBox="0 0 579.06 242.58"><title>Atlantic.Net</title><path class="a" d="M107.93,251.59q0,6.91-2.51,10.65a8,8,0,0,1-7,3.74,6.74,6.74,0,0,1-5.27-2.33,8.72,8.72,0,0,1-2.07-6,11.62,11.62,0,0,1,4.54-9.16q4.55-3.83,12.32-4.84v8Zm8.76,25.32a19.45,19.45,0,0,0,9.26,2c0.79,0,1.4,0,1.81,0s0.79-.06,1.13-0.11l0.06-13.32a4.09,4.09,0,0,1-2.38-1.48,4.39,4.39,0,0,1-.83-2.73V231.81q0-11.67-6.53-17.6t-19.28-5.93a40.73,40.73,0,0,0-13.63,2.19,38.16,38.16,0,0,0-11.62,6.63l8.38,10.72a38.54,38.54,0,0,1,8.35-5.28,18.59,18.59,0,0,1,7.47-1.68,10.41,10.41,0,0,1,6.56,1.93,6.09,6.09,0,0,1,2.48,5v5.35q-17,2.32-25.52,9.26t-8.48,18.42q0,8.54,4.74,13.72t12.6,5.18a22.26,22.26,0,0,0,9.74-2.2,36.71,36.71,0,0,0,9.49-7A15.41,15.41,0,0,0,116.68,276.91Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M144.61,279.91V222.26H129.36V208.53h46.19v13.73H160v57.65H144.61Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M211.59,279.66h-7.74c-15.36,0-22.41-7.17-22.41-21.44V208.38h17.21s0.14,43.42.14,48.42c0,4.49,2.29,7.1,6.51,7.1h6.2Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M249.22,251.71q0,6.88-2.5,10.6a8,8,0,0,1-7,3.72,6.71,6.71,0,0,1-5.24-2.31,8.67,8.67,0,0,1-2.06-6,11.57,11.57,0,0,1,4.53-9.13q4.53-3.82,12.27-4.82v7.94Zm8.72,25.21a19.34,19.34,0,0,0,9.22,2q1.18,0,1.81,0t1.12-.11l0.06-13.27a4.07,4.07,0,0,1-2.37-1.47,4.38,4.38,0,0,1-.83-2.72V232q0-11.62-6.5-17.52t-19.2-5.91a40.61,40.61,0,0,0-13.57,2.18,38,38,0,0,0-11.57,6.61L224.45,228a38.42,38.42,0,0,1,8.32-5.26,18.51,18.51,0,0,1,7.44-1.67,10.35,10.35,0,0,1,6.53,1.92,6.06,6.06,0,0,1,2.47,5v5.33q-17,2.31-25.41,9.22t-8.45,18.35q0,8.5,4.72,13.66t12.55,5.16a22.22,22.22,0,0,0,9.7-2.18,36.61,36.61,0,0,0,9.45-6.93A15.3,15.3,0,0,0,257.94,276.92Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M277.6,279.69V209.93h18.16v13.31q5.23-7.63,10.5-11.22a19.54,19.54,0,0,1,11.2-3.59q7.08,0,10.91,4.39t3.83,12.41v54.46H314.05V236.22q0-6.84-1.28-8.85t-4.72-2a11.78,11.78,0,0,0-5.77,1.76,31.56,31.56,0,0,0-6.53,5.21v47.36H277.6Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M415.44,238.41q0-10.4,1.36-15.17a18.89,18.89,0,0,1,4.65-8.16,19.89,19.89,0,0,1,7.32-4.68,27.28,27.28,0,0,1,9.62-1.61q9.76,0,16.23,5.47a16.92,16.92,0,0,1,6.46,13.42v4.09H446.22q-0.18-5.22-2-7.58t-5.76-2.36q-4.37,0-6.06,2.38t-1.69,11.63v17.06q0,8.83,1.67,11.42t6.08,2.58q4.14,0,5.94-2.52t1.8-8.36v-1h14.91v4.53a19,19,0,0,1-6.26,14.79Q448.57,280,438.4,280a27.33,27.33,0,0,1-9.62-1.6,19.91,19.91,0,0,1-7.32-4.68,18.88,18.88,0,0,1-4.65-8.16q-1.36-4.77-1.36-15.17v-12Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M494,279.73v-69.8h18.17v13.31q5.24-7.63,10.51-11.22a19.55,19.55,0,0,1,11.21-3.59q7.09,0,10.92,4.4t3.83,12.41v54.49H530.47V236.24q0-6.84-1.28-8.86t-4.72-2a11.8,11.8,0,0,0-5.77,1.76,31.63,31.63,0,0,0-6.54,5.21v47.39H494Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M571.85,231.28q0-5.1,2.19-8a7.84,7.84,0,0,1,12.16-.06q2.06,2.86,2.07,8.52v5.84H571.85v-6.28Zm29.58,30a53.77,53.77,0,0,1-8.81,3.4,28.18,28.18,0,0,1-7.44,1.11q-6.33,0-9.83-3.23t-3.5-9.06v-5.86h31.39V233q0-11.36-6.33-17.88t-17.32-6.52q-11.8,0-18,7t-6.24,20.31v16q0,13.47,6.86,20.61T582,279.67a47.23,47.23,0,0,0,10.4-1.21,69.07,69.07,0,0,0,11.21-3.63Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M352.28,279.92V222.26H337V208.54h46.19v13.73H367.7v57.65H352.28Z" transform="translate(-73.92 -37.44)"/><polygon class="a" points="315.72 170.94 333.44 170.94 333.44 242.22 315.78 242.22 315.72 170.94"/><path class="a" d="M622,279.71V222.05H606.79V208.33H653v13.73H637.45v57.65H622Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M370.37,108.79s26.45-7.19,24.74-18.73c-2-13.41-35.32-14.31-57.61-14.31L344,90.06s22.49-1.48,27.88,2C376.5,95,375.51,99.56,370.37,108.79Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M403.85,95.26s41.52-37.66-89.4-33.93c-97.54,2.78-121.72,35-121.72,35s24.81-42.85,125.62-45.47C458,47.26,407,94.48,403.85,95.26Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M392,112.26S469.31,101.08,465.86,71c-3.64-31.74-95.23-32.9-95.23-32.9s131.49-8.24,133.15,33.17C505.47,113.15,392,112.26,392,112.26Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M337.13,93.63s-29,6.62-25.48,19C315.52,126.15,348.59,131,370,130.8l-8.84-16.89s-19.4-.67-26.16-4.31C328.58,106.16,327.85,101.92,337.13,93.63Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M301.57,105.71S262.4,151,413.91,150.48C553.6,150,534,97,534,97s33.81,64.13-123.89,65.13C311.14,162.78,275.89,134.21,301.57,105.71Z" transform="translate(-73.92 -37.44)"/><path class="a" d="M317.12,89.25s-80.2,15.78-76.73,52.57c3.3,35.07,116.94,40.2,116.94,40.2s-151.71,4.33-155.48-37.21C197.49,96.8,317.12,89.25,317.12,89.25Z" transform="translate(-73.92 -37.44)"/><circle class="a" cx="403.41" cy="231.66" r="10.51"/></svg>
			<h2 class="h2">$reportTitle</h2><h3 class="h3">$reportDate</h3>
		</div>
        <div class="row" style="margin-bottom:20px;">
            <div class="col-xs-6 col-md-6">
                <div class="panel panel-info">
                    <div class="panel-heading">
                        <h3 class="vmname">Quick Stats</h3>
                    </div>
                    <div class="panel-body">
                        <p class="text-center">
							<div class="row">
								<div class="col-xs-4 col-md-4">
									<div class="panel panel-success">
										<div class="panel-heading">
											Online vCPUs
											<span class="badge">
											$(($VMs | Where-Object status -eq "running" | Measure-Object cpus -Sum).Sum)
											</span>
										</div>
									</div>
								</div>
								<div class="col-xs-4 col-md-4">
									<div class="panel panel-info">
										<div class="panel-heading">
											Total vCPUs
											<span class="badge">
											$(($VMs | Measure-Object cpus -Sum).Sum)
											</span>
										</div>
									</div>
								</div>
								<div class="col-xs-4 col-md-4">
									<div class="panel panel-primary">
										<div class="panel-heading">
											Physical CPUs
											<span class="badge">
											$($HostProcessors.maxcpu)
											</span>
										</div>
									</div>
								</div>
                            </div>
                        </p>
                        <div class="progress">
                            <div class="progress-bar progress-bar-success active" style="width:$(if(($runningVMs+$runningLXCs) -gt 0){(($runningVMs+$runningLXCs)/($totalVMs+$totalLXCs))*100}else{0})%">
                                <span>$runningVMs VMs & $runningLXCs LXCs Online</span>
                            </div>
                            <div class="progress-bar progress-bar-warning " style="width:$(if(($pausedVMs+$pausedLXCs) -gt 0){(($pausedVMs+$pausedLXCs)/($totalVMs+$totalLXCs))*100}else{0})%">
                                <span>$pausedVMs VMs & $pausedLXCs LXCs Paused</span>
                            </div>
                            <div class="progress-bar progress-bar-danger" style="width:$(if(($offlineVMs+$offlineLXCs) -gt 0){(($offlineVMs+$offlineLXCs)/($totalVMs+$totalLXCs))*100}else{0})%">
                                <span>$offlineVMs VMs & $offlineLXCs LXCs Offline</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="col-xs-6 col-md-6">
                <div class="panel panel-$memoryOnlineProgressBar">
                    <div class="panel-heading">
                        <h3 class="vmname">Memory Usage</h3>
                    </div>
                    <table class="table table-striped table-condensed text-center">
                        <tr>
                            <th>Current Use</th>
                            <th>Running Max</th>
                            <th>Total Max</th>
                            <th>System Memory</th>
                        </tr>
                        <tr>
                            <td>$("{0:N2}" -f ($TotalRamCurrent/1gb -as [float]))</td>
                            <td>$("{0:N2}" -f ($TotalRamOnline/1gb -as [float]))</td>
                            <td>$("{0:N2}" -f ($TotalRamMax/1gb -as [float]))</td>
                            <td>$("{0:N2} GB" -f ($HostMemory.maxmem/1gb -as [float]))</td>
                        </tr>
                    </table>
                    <div class="panel-body">
                        <div class="progress" style="margin-bottom:2px;">
                            <div class="progress-bar progress-bar-$memoryCurrentProgressBar active" 
                                aria-valuenow="$ramCurrentPercent" aria-valuemin="0" 
                                aria-valuemax="100" style="width:$ramCurrentPercent%">
                                <span>Current</span>
                            </div>
                            <div class="progress-bar progress-bar-$memoryOnlineProgressBar" 
                                aria-valuenow="$ramOnlinePercent" aria-valuemin="0" 
                                aria-valuemax="100" style="width:$ramOnlinePercent%">
                                <span>Online</span>
                            </div>
                            <div class="progress-bar progress-bar-$memoryMaxProgressBar" 
                                aria-valuenow="$ramMaxPercent" aria-valuemin="0" 
                                aria-valuemax="100" style="width:$ramMaxPercent%">
                                <span>Total</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="row" style="margin-bottom:20px;">
            <div class="col-xs-12 col-md-12">
                <div class="panel panel-primary">
                    <div class="panel-heading">
                        <h3 class="vmname"><span class="glyphicon glyphicon-hdd"></span> Hard Drives</h3>
                    </div>
                    <div class="panel-body" style="padding-top:0;padding-bottom:0;">
                    	$harddriveString
                    </div>
                </div>
            </div>
        </div>
        <div class="row">
            <div class="col-xs-12 col-md-12">
                <div class="panel panel-primary">
                    <div class="panel-heading" style="margin-bottom:5px;">
                        <h3 class="vmname"><span class="glyphicon glyphicon-blackboard"></span> Virtual Machines</h3>
                    </div>
                    <div class="panel-body" style="padding-top:0;padding-bottom:0;">
                        <div class="row text-center">
                            <div class="col-xs-3 col-md-3"><h4 class="vmname">Name</h4></div>
                            <div class="col-xs-3 col-md-3"><h4 class="vmname">Memory</h4></div>
                            <div class="col-xs-6 col-md-6"><h4 class="vmname">Hard Drives</h4></div>
						</div>
                        $vms_string
                    </div>
                </div>
            </div>
        </div>
        <div class="row">
            <div class="col-xs-12 col-md-12">
                <div class="panel panel-primary">
                    <div class="panel-heading" style="margin-bottom:5px;">
                    <h3 class="vmname"><span class="glyphicon glyphicon-blackboard"></span> Containers</h3>
                    </div>
                    <div class="panel-body" style="padding-top:0;padding-bottom:0;">
                        <div class="row text-center">
                            <div class="col-xs-3 col-md-3"><h4 class="vmname">Name</h4></div>
                            <div class="col-xs-3 col-md-3"><h4 class="vmname">Memory</h4></div>
                            <div class="col-xs-6 col-md-6"><h4 class="vmname">Hard Drives</h4></div>
				        </div>
                        $lxcs_string
                    </div>
                </div>
            </div>
        </div>
"@

        $body +=
        @"
        <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js" integrity="sha384-0mSbJDEHialfmuBBQP6A4Qrprq5OVfW37PRR3j5ELqxss1yVqOtnepnHVP9aJ7xS" crossorigin="anonymous"></script>
        <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
    </div>
"@
        #endregion ::: BODY HTML

        #CREATE THE HTML FILE::Defaults to C:\
        #ConvertTo-Html -Title $reportTitle -Head $header -Body $body | Set-Content "C:\$reportTitle on $reportDate.htm"


        #region Create PDF
        #---- Note that this only will work if there is an internet connection, as it has to reach out to the API ---#
        #---- This uses pdflayer.com's API. The margins need to be set to 0 all the time to avoid the tables being --#
        #---- Shoved off the ends of the page. If DEVELOPING, please change the test variable to 1 ------------------#

        $document_html = ConvertTo-Html -Title $reportTitle -Head $header -Body $body

        #Make sure test is set to 1 if developing!!!!
        $test = 1
        # support@atlantic.net access key for pdflayer.com
        $access_key = "9645192ce6040a9ae18f658104b2428b"

        $api_uri = "http://api.pdflayer.com/api/convert?access_key=$access_key&test=$test&margin_bottom=0&margin_top=0&margin_right=0&margin_left=0"

        $api_body = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $api_body.Add("document_html" , $document_html)

        Invoke-RestMethod -Method Post -Uri $api_uri -Body $api_body -Verbose -OutFile "$([Environment]::GetFolderPath("Desktop"))\$reportTitle on $reportDate.pdf"

        #endregion Create PDF

        #region Clear variables
        Remove-Variable body
        Remove-Variable header
        Remove-Variable TotalRamMax
        Remove-Variable TotalRamCurrent
        Remove-Variable TotalRamOnline
        Remove-Variable hddMaxPercent 
        Remove-Variable hddOnlinePercent 
        Remove-Variable hddCurrentPercent
        Remove-Variable ramOnlinePercent
        Remove-Variable ramCurrentPercent
        Remove-Variable ramMaxPercent
        Remove-Variable harddriveString
        Remove-Variable runningLXCs
        Remove-Variable pausedLXCs
        Remove-Variable offlineLXCs
        Remove-Variable totalLXCs
        Remove-Variable api_uri
        #endregion Clear Variables

        #region API/PDF Clear Vars

        #endregion AP/PDF Clear Vars



        #OPEN THE HTML FILE
        Invoke-Item "$([Environment]::GetFolderPath("Desktop"))\$reportTitle on $reportDate.pdf"
        #BYE
    }

}
Remove-Variable session
Remove-Variable VHD_temp
Remove-Variable nodes
Remove-Variable qemus
Remove-Variable lxcs
Remove-Variable storages
Remove-Variable content
Remove-Variable tempcontent
Remove-Variable api_body
Remove-Variable document_html
Remove-Variable access_key
Remove-Variable uri