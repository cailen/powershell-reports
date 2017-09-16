#region ::: Variables
$TotalRamMax = 0.00
$TotalRamCurrent = 0.00
$TotalRamOnline = 0.00
$HostMemory = Get-VMHost | Select-Object MemoryCapacity
$HostProcessors = Get-VMHost | Select-Object LogicalProcessorCount
$VMs = Get-VM
$runningVMs = ($VMs | Where-Object State -eq "Running" | Measure-Object).Count
$pausedVMs = ($VMs | Where-Object {($_.State -eq "Paused") -or ($_.State -eq "Saved")} | Measure-Object).Count
$offlineVMs = ($VMs | Where-Object State -eq "Off" | Measure-Object).Count
$totalVMs = ($VMs).Count
$reportTitle = "Hyper-V Report for $((Get-VMHost).Name)"
$reportDate = "$(Get-Date -Format "MM-dd-yyyy")"
$driveLetters = Get-PSDrive -PSProvider 'FileSystem' | Select-Object Name, Used, Free 
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
#endregion ::: Variables

#region ::: Get the memory and hard drive stats from the VMs
Foreach ($VM in $VMs) {
    $TotalRamMax += $VM.MemoryStartup
    $TotalRamCurrent += $VM.MemoryAssigned
    
    if ($VM.State -eq "Running") {
        $TotalRamOnline += $VM.MemoryStartup
    } 

    $VHDs = $VM | Get-VMHardDiskDrive | Get-VHD | Select-Object Path, FileSize, Size


    #Fill the drive stats dictionary (Key=Drive Letter, Value=Size)
    foreach ($VHD in $VHDs) {
        $driveArrCurrent[$VHD.Path.Substring(0, 1)] += 0.0
        $driveArrOnline[$VHD.Path.Substring(0, 1)] += 0.0

        if ($VM.State -eq "Running") {
            if ($driveArrMax.ContainsKey($VHD.Path.Substring(0, 1))) {
                $driveArrMax[$VHD.Path.Substring(0, 1)] += $VHD.Size -as [float]
                $driveArrCurrent[$VHD.Path.Substring(0, 1)] += $VHD.FileSize
                $driveArrOnline[$VHD.Path.Substring(0, 1)] += $VHD.Size
            }
            else {
                $driveArrMax[$VHD.Path.Substring(0, 1)] += $VHD.Size -as [float]
                $driveArrCurrent[$VHD.Path.Substring(0, 1)] += $VHD.FileSize -as [float]
                $driveArrOnline[$VHD.Path.Substring(0, 1)] += $VHD.Size -as [float]
                $driveArrFree.Add($VHD.Path.Substring(0, 1), ($driveLetters | Where-Object Name -ieq $VHD.Path.Substring(0, 1) | Select-Object Free))
                $driveArrUsed.Add($VHD.Path.Substring(0, 1), ($driveLetters | Where-Object Name -ieq $VHD.Path.Substring(0, 1) | Select-Object Used))
            }
        }
        else {
            if ($driveArrMax.ContainsKey($VHD.Path.Substring(0, 1))) {
                $driveArrMax[$VHD.Path.Substring(0, 1)] += $VHD.Size
            }
            else {
                $driveArrMax[$VHD.Path.Substring(0, 1)] += $VHD.Size
                $driveArrFree.Add($VHD.Path.Substring(0, 1), ($driveLetters | Where-Object Name -ieq $VHD.Path.Substring(0, 1) | Select-Object Free))
                $driveArrUsed.Add($VHD.Path.Substring(0, 1), ($driveLetters | Where-Object Name -ieq $VHD.Path.Substring(0, 1) | Select-Object Used))
            }
        }
    }
}
#endregion ::: Get the memory and hard drive stats from the VMs

#region ::: HDD Progress Bar Calculations
#=============================

#Go through each drive
foreach ($driveFor in $driveArrMax.GetEnumerator()) {
    $HostDriveTotal = ($driveArrFree[$driveFor.Key].Free + $driveArrUsed[$driveFor.Key].Used)

    #find out the percentages
    [float]$hddMaxPercent = ("{0:N2}" -f ((($driveArrMax.Get_Item($driveFor.Key)) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))
    [float]$hddUsedPercent = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].Used) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))
    
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
                                            <div class="progress-bar progress-bar-$hddCurrentProgressBar progress-bar-striped active"
                                                aria-valuenow="$hddCurrentPercent" aria-valuemin="0" 
                                                aria-valuemax="100" style="width:$hddCurrentPercent%">
                                                <span>Current</span>
                                            </div>
                                            <div class="progress-bar progress-bar-$hddOnlineProgressBar progress-bar-striped" 
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
                                                <td>$("{0:N2}" -f (($driveArrFree[$driveFor.Key].Free)/1gb -as [float]))</td>
                                                <td>$("{0:N2} GB" -f ($HostDriveTotal/1gb -as [float]))</td>
                                            </tr>
                                        </table>
                                        <div class="progress">
                                            <div class="progress-bar progress-bar-$hddUsedProgressBar progress-bar-striped active"
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

[float]$ramMaxPercent = ("{0:N2}" -f (($TotalRamMax / 1gb -as [float]) / ($HostMemory.MemoryCapacity / 1gb -as [float]) * 100))
[float]$ramOnlinePercent = ("{0:N2}" -f (($TotalRamOnline / 1gb -as [float]) / ($HostMemory.MemoryCapacity / 1gb -as [float]) * 100))
[float]$ramCurrentPercent = ("{0:N2}" -f (($TotalRamCurrent / 1gb -as [float]) / ($HostMemory.MemoryCapacity / 1gb -as [float]) * 100))

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
    $HardDrives = $VM.HardDrives
    $VM_style = ""
    $VM_state = ""

    [float]$VHD_Used = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].Used) / 1gb -as [float]) / ($HostDriveTotal / 1gb -as [float]) * 100))

    $(Switch ($VM.State) {
            "Running" {$VM_style = "success"; $VM_state = '<span class="glyphicon glyphicon-play" style="font-size:1.6em;"></span>'; break; }
            "Paused" {$VM_style = "warning"; $VM_state = '<span class="glyphicon glyphicon-pause" style="font-size:1.6em;"></span>'; break; }
            "Off" {$VM_style = "danger"; $VM_state = '<span class="glyphicon glyphicon-stop" style="font-size:1.6em;"></span>'; break; }
            "Saved" {$VM_style = "warning"; $VM_state = '<span class="glyphicon glyphicon-save" style="font-size:1.6em;"></span>'; break; }
            default {$VM_style = "info"; $VM_state = '<span class="glyphicon glyphicon-asterisk" style="font-size:1.6em;"></span>'; break; }
        })

    foreach ($HardDrive in $HardDrives) {
        $VHD_temp = $HardDrive.path | Get-VHD
        [float]$vhd_UsedPercent = ("{0:N2}" -f ($VHD_temp.FileSize / 1gb –as [float]) / ($VHD_temp.Size / 1gb –as [float]) * 100)

        switch ($vhd_UsedPercent) {
            {$vhd_UsedPercent -gt 90.00} {$vhd_ProgressBar = "danger"; break}
            {$vhd_UsedPercent -gt 75.00} {$vhd_ProgressBar = "warning"; break}
            default {$vhd_ProgressBar = "success"}
        }

        $vhd_table += @"
<tr>
    <td>$($HardDrive.path.Substring(0,1))</td>
    <td>$($HardDrive.ControllerLocation)</td>
    <td>$("{0:N2} GB" -f ($VHD_temp.FileSize/1gb –as [float]))</td>
    <td>$("{0:N2} GB" -f ($VHD_temp.Size/1gb –as [float]))</td>
    <td>
        <div class="progress">
            <div class="progress-bar progress-bar-$vhd_ProgressBar progress-bar-striped" 
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
					<h4 class="h4">$($VM.Name)</h4>
					<span class="badge">$($VM.ProcessorCount) vCPU</span>
					$VM_state
				</div>
			</div>
		</div>
		<div class="col-xs-3">
			<h4 class="text-center">$("{0:N2}" -f ($VM.MemoryAssigned/1gb -as [float])) of $("{0:N2} GB" -f ($VM.MemoryStartup/1gb -as [float]))</h4>
			<div class="progress">
                <div class="progress-bar progress-bar-primary" role="progressbar" 
                    aria-valuenow="$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100))" aria-valuemin="0" aria-valuemax="100" style="width:$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100))%">
                </div>
            </div>
		</div>
		<div class="col-xs-6">
			<table class="table table-striped table-condensed text-center" style="margin-bottom:2px;">
                <thead>
                    <tr>
                        <th>Loc</th>
                        <th>Disk</th>
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
            background: #0099cc;
            color: #ffffff;
            border: 0;
        }
        
        .btn-success {
            background: #66BB6A;
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
            background: #00BCD4;
            color: #ffffff;
            border: 0;
        }
        
        .panel {
            border: 0;
            box-shadow: 0 4px 5px 0 rgba(0, 0, 0, .14), 0 1px 10px 0 rgba(0, 0, 0, .12), 0 2px 4px -1px rgba(0, 0, 0, .2);
        }
        
        .panel-success> .panel-heading {
            background: #66BB6A;
            color: #ffffff;
            border: 0;
        }
        
        .panel-primary> .panel-heading {
            background: #00BCD4;
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
            background: #80DEEA;
            color: #ffffff;
        }
        
        body {
            background: #78909C;
        }
        
        .container {
            background: #ECEFF1;
        }
        
        .progress {
            background: #CFD8DC;
        }
        
        .progress> .progress-bar-primary {
            background: #0099cc;
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
				background: #fff;
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
        <div class="jumbotron text-center" style="background-color: #00BCD4; color:white; height:300px; padding-top:10px; padding-bottom:10px; margin-bottom:20px;">
			<h1 class="h1">$reportTitle</h1><h2 class="h2">$reportDate</h2>
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
											$(($VMs | Where-Object State -eq "Running" | Measure-Object ProcessorCount -Sum).Sum)
											</span>
										</div>
									</div>
								</div>
								<div class="col-xs-4 col-md-4">
									<div class="panel panel-info">
										<div class="panel-heading">
											Total vCPUs
											<span class="badge">
											$(($VMs | Measure-Object ProcessorCount -Sum).Sum)
											</span>
										</div>
									</div>
								</div>
								<div class="col-xs-4 col-md-4">
									<div class="panel panel-primary">
										<div class="panel-heading">
											Physical CPUs
											<span class="badge">
											$($HostProcessors.LogicalProcessorCount)
											</span>
										</div>
									</div>
								</div>
                            </div>
                        </p>
                        <div class="progress">
                            <div class="progress-bar progress-bar-success progress-bar-striped active" style="width:$(($runningVMs/$totalVMs)*100)%">
                                <span>$runningVMs Online VMs</span>
                            </div>
                            <div class="progress-bar progress-bar-warning progress-bar-striped" style="width:$(($pausedVMs/$totalVMs)*100)%">
                                <span>$pausedVMs Paused VMs</span>
                            </div>
                            <div class="progress-bar progress-bar-danger" style="width:$(($offlineVMs/$totalVMs)*100)%">
                                <span>$offlineVMs Offline VMs</span>
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
                            <td>$("{0:N2} GB" -f ($HostMemory.MemoryCapacity/1gb -as [float]))</td>
                        </tr>
                    </table>
                    <div class="panel-body">
                        <div class="progress" style="margin-bottom:2px;">
                            <div class="progress-bar progress-bar-$memoryCurrentProgressBar progress-bar-striped active" 
                                aria-valuenow="$ramCurrentPercent" aria-valuemin="0" 
                                aria-valuemax="100" style="width:$ramCurrentPercent%">
                                <span>Current</span>
                            </div>
                            <div class="progress-bar progress-bar-$memoryOnlineProgressBar progress-bar-striped" 
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
"@

$body +=
@"
        <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js" integrity="sha384-0mSbJDEHialfmuBBQP6A4Qrprq5OVfW37PRR3j5ELqxss1yVqOtnepnHVP9aJ7xS" crossorigin="anonymous"></script>
        <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
    </div>
"@
#endregion ::: BODY HTML

#region Create PDF
#---- Note that this only will work if there is an internet connection, as it has to reach out to the API ---#
#---- This uses pdflayer.com's API. The margins need to be set to 0 all the time to avoid the tables being --#
#---- Shoved off the ends of the page. If DEVELOPING, please change the test variable to 1 ------------------#

$document_html = ConvertTo-Html -Title $reportTitle -Head $header -Body $body
$test = 1
# Your access key for pdflayer.com
$access_key = *** YOUR API KEY HERE ***

$uri = "http://api.pdflayer.com/api/convert?access_key=$access_key&test=$test&margin_bottom=0&margin_top=0&margin_right=0&margin_left=0"

$api_body = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$api_body.Add("document_html" , $document_html)

Invoke-RestMethod -Method Post -Uri $uri -Body $api_body -Verbose -OutFile "$([Environment]::GetFolderPath("Desktop"))\$reportTitle on $reportDate.pdf"

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
Remove-Variable VHD_temp
#endregion Clear Variables

#region API/PDF Clear Vars
Remove-Variable api_body
Remove-Variable document_html
Remove-Variable access_key
Remove-Variable uri
#endregion AP/PDF Clear Vars

#OPEN THE HTML FILE
Invoke-Item "$([Environment]::GetFolderPath("Desktop"))\$reportTitle on $reportDate.pdf"
#BYE