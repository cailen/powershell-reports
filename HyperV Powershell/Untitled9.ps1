﻿#region ::: Variables
$TotalHddMax = 0.00
$TotalHddCurrent = 0.00
$TotalHddOnline = 0.00
$TotalRamMax = 0.00
$TotalRamCurrent = 0.00
$TotalRamOnline = 0.00
$HostMemory = Get-VMHost | Select MemoryCapacity
$HostProcessors = Get-VMHost | Select LogicalProcessorCount
$VMs = Get-VM
$runningVMs = ($VMs | Where State -eq "Running" | Measure).Count
$pausedVMs = ($VMs | Where {($_.State -eq "Paused") -or ($_.State -eq "Saved")} | Measure).Count
$offlineVMs = ($VMs | Where State -eq "Off" | Measure).Count
$totalVMs = ($VMs).Count
$reportTitle = "Hyper-V Report for $((Get-VMHost).Name)"
$reportDate = "$(Get-Date -Format "MM-dd-yyyy")"
$driveLetters = gdr -PSProvider 'FileSystem' | Select Name, Used, Free 
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
#endregion ::: Variables

#region ::: Get the memory and hard drive stats from the VMs
Foreach ($VM in $VMs)
{
    $TotalRamMax += $VM.MemoryStartup
    $TotalRamCurrent += $VM.MemoryAssigned
    
    if($VM.State -eq "Running")
    {
        $TotalRamOnline += $VM.MemoryStartup
    } 

    $VHDs = $VM | Get-VMHardDiskDrive | Get-VHD | Select Path, FileSize, Size


    #Fill the drive stats dictionary (Key=Drive Letter, Value=Size)
    foreach($VHD in $VHDs)
    {
        if($VM.State -eq "Running")
        {
            if($driveArrMax.ContainsKey($VHD.Path.Substring(0,1)))
            {
                $driveArrMax[$VHD.Path.Substring(0,1)] += $VHD.Size -as [float]
                $driveArrCurrent[$VHD.Path.Substring(0,1)] += $VHD.FileSize
                $driveArrOnline[$VHD.Path.Substring(0,1)] += $VHD.Size
            }
            else
            {
                $driveArrMax[$VHD.Path.Substring(0,1)] += $VHD.Size -as [float]
                $driveArrCurrent[$VHD.Path.Substring(0,1)] += $VHD.FileSize -as [float]
                $driveArrOnline[$VHD.Path.Substring(0,1)] += $VHD.Size -as [float]
                $driveArrFree.Add($VHD.Path.Substring(0,1),($driveLetters | Where Name -ieq $VHD.Path.Substring(0,1) | Select Free))
                $driveArrUsed.Add($VHD.Path.Substring(0,1),($driveLetters | Where Name -ieq $VHD.Path.Substring(0,1) | Select Used))
            }
        }
        else
        {
            if($driveArrMax.ContainsKey($VHD.Path.Substring(0,1)))
            {
                $driveArrMax[$VHD.Path.Substring(0,1)] += $VHD.Size
            }
            else
            {
                $driveArrMax[$VHD.Path.Substring(0,1)] += $VHD.Size
                $driveArrFree.Add($VHD.Path.Substring(0,1),($driveLetters | Where Name -ieq $VHD.Path.Substring(0,1) | Select Free))
                $driveArrUsed.Add($VHD.Path.Substring(0,1),($driveLetters | Where Name -ieq $VHD.Path.Substring(0,1) | Select Used))
            }
        }
    }
}
#endregion ::: Get the memory and hard drive stats from the VMs

#region ::: HDD Progress Bar Calculations
#=============================

#Go through each drive
foreach ($driveFor in $driveArrMax.GetEnumerator())
{
    $HostDriveTotal = ($driveArrFree[$driveFor.Key].Free + $driveArrUsed[$driveFor.Key].Used)

    #find out the percentages
    [float]$hddMaxPercent = ("{0:N2}" -f ((($driveArrMax.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddUsedPercent = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].Used)/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddOnlinePercent = ("{0:N2}" -f ((($driveArrOnline.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddCurrentPercent = ("{0:N2}" -f ((($driveArrCurrent.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))

    #region ::: setup the progress bar percentages (in other words, if they're over 100%, set them to 100%
    switch($hddUsedPercent)
    {
        {$hddUsedPercent -gt 90.00} {$hddUsedProgressBar = "danger"; break}
        {$hddUsedPercent -gt 75.00} {$hddUsedProgressBar = "warning"; break}
        default {$hddUsedProgressBar = "success"}
    }

    if($hddMaxPercent -gt 100){$hddMaxPercent = 100.00;}
    if($hddCurrentPercent -gt 100)
    {
        $hddCurrentPercent = 100.00 
        $hddGlyph = '<span class="glyphicon glyphicon-remove" style="color:red"/>'
    }
    if($hddOnlinePercent -ge 100)
    {
        $hddOnlinePercent = 100.00
        $hddGlyph = '<span class="glyphicon glyphicon-remove" style="color:red"/>'
    }

    switch($hddOnlinePercent)
    {
        {$hddOnlinePercent -gt 90.00} {$hddContainer = "danger"; $hddGlyph = '<span class="glyphicon glyphicon-remove" style="color:red"/>'; break}
        {$hddOnlinePercent -gt 75.00} {$hddContainer = "warning"; $hddGlyph = '<span class="glyphicon glyphicon-warning-sign" style="color:yellow"/>'; break}
        default {$hddContainer = "success"; $hddGlyph = '<span class="glyphicon glyphicon-ok" style="color:green"/>'; break}
    }

    $hddMaxProgressBar = "danger"
    $hddOnlineProgressBar = "success"
    $hddCurrentProgressBar = "info"

    switch ($hddOnlinePercent)
    {
        {$hddOnlinePercent -gt 90.00} {$hddOnlineProgressBar = "danger"; break}
        {$hddOnlinePercent -gt 75.00} {$hddOnlineProgressBar = "warning"; break}
        default {$hddOnlineProgressBar = "success"}
    }
    switch ($hddCurrentPercent)
    {
        {$hddCurrentPercent -gt 90.00} {$hddCurrentProgressBar = "danger"; break}
        {$hddCurrentPercent -gt 75.00} {$hddCurrentProgressBar = "warning"; break}
        default {$hddCurrentProgressBar = "info"}
    }
    #endregion ::: setup the progress bar percentages (in other words, if they're over 100%, set them to 100%

    #region ::: adjust the percentages for the progress bar
    #IF ONLINE IS BIGGER THAN MAX, MAX IS GOING TO BE 0
    if ($hddOnlinePercent -ge $hddMaxPercent)
    {
        #IF CURRENT IS BIGGER THAN ONLINE, BOTH MAX AND ONLINE ARE 0
        if($hddCurrentPercent -ge $hddOnlinePercent)
        {    
            $hddOnlinePercent = 0
            $hddMaxPercent = 0
        }
        #IF ONLINE IS BIGGER THAN CURRENT, CURRENT STAYS THE SAME AND ONLINE IS THE REMAINDER
        else
        {
            $hddOnlinePercent = ($hddOnlinePercent - $hddCurrentPercent)
            $hddMaxPercent = 0
        }
    }
    #IF MAX IS BIGGER THAN ONLINE, MAX IS THE REMAINDER
    elseif($hddMaxPercent -ge $hddOnlinePercent)
    {
        #IF MAX IS BIGGER THAN CURRENT, MAX and ONLINE ARE REMAINDERS
        if ($hddMaxPercent -ge $hddCurrentPercent)
        {
            $hddOnlinePercent = ($hddOnlinePercent - $hddCurrentPercent)
            $hddMaxPercent = ($hddMaxPercent - ($hddOnlinePercent + $hddCurrentPercent))
        }
        #IF CURRENT IS BIGGER THAN MAX, MAX IS 0 AND ONLINE IS THE REMAINDER
        else
        {  
            $hddOnlinePercent = ($hddOnlinePercent - $hddCurrentPercent)
            $hddMaxPercent = 0
        }
    }
    else
    # if($hddCurrentPercent -ge $hddOnlinePercent)
    # Since current usage is higher than other metrics, the rest are set to 0
    {
        $hddOnlinePercent = 0
        $hddMaxPercent = 0
    }
    #endregion ::: adjust the percentages for the progress bar

    #String for the Hard Drives Summary
    $harddriveString += @"
                            <div class="col-xs-12 col-md-12 bg-$hddContainer">
                                <h4 class="vmname">Hard Drive `($($driveFor.Key)`:) Usage $hddGlyph</h4>
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
"@
}

#=====================
#endregion ::: HDD Calculations

#region ::: RAM Progress Bar Calculations
#=============================

[float]$ramMaxPercent = ("{0:N2}" -f (($TotalRamMax/1gb -as [float])/($HostMemory.MemoryCapacity/1gb -as [float]) * 100))
[float]$ramOnlinePercent = ("{0:N2}" -f (($TotalRamOnline/1gb -as [float])/($HostMemory.MemoryCapacity/1gb -as [float]) * 100))
[float]$ramCurrentPercent = ("{0:N2}" -f (($TotalRamCurrent/1gb -as [float])/($HostMemory.MemoryCapacity/1gb -as [float]) * 100))

if($ramMaxPercent -gt 100){$ramMaxPercent = 100}
if($ramCurrentPercent -gt 100){$ramCurrentPercent = 100}
if($ramOnlinePercent -gt 100){$ramOnlinePercent = 100}   

$memoryMaxProgressBar = "danger"
$memoryOnlineProgressBar = "success"
$memoryCurrentProgressBar = "info"

switch ($ramOnlinePercent)
{
    {$_ -gt 90.00} {$memoryOnlineProgressBar = "danger"; break}
    {$_ -gt 75.00} {$memoryOnlineProgressBar = "warning"; break}
    default {$memoryOnlineProgressBar = "success"}
}
switch ($ramCurrentPercent)
{
    {$_ -gt 90.00} {$memoryCurrentProgressBar = "danger"; break}
    {$_ -gt 75.00} {$memoryCurrentProgressBar = "warning"; break}
    default {$memoryCurrentProgressBar = "info"}
}

#region ::: Adjust the percentages for the progress bar
#IF ONLINE IS BIGGER THAN MAX, MAX IS GOING TO BE 0
if ($ramOnlinePercent -ge $ramMaxPercent)
{
    #IF CURRENT IS BIGGER THAN ONLINE, BOTH MAX AND ONLINE ARE 0
    if($ramCurrentPercent -ge $ramOnlinePercent)
    {    
        $ramOnlinePercent = 0
        $ramMaxPercent = 0
    }
    #IF ONLINE IS BIGGER THAN CURRENT, CURRENT STAYS THE SAME AND ONLINE IS THE REMAINDER
    else
    {
        $ramOnlinePercent = ($ramOnlinePercent - $ramCurrentPercent)
        $ramMaxPercent = 0
    }
}
#IF MAX IS BIGGER THAN ONLINE, MAX IS THE REMAINDER
elseif($ramMaxPercent -ge $ramOnlinePercent)
{
    #IF MAX IS BIGGER THAN CURRENT, MAX and ONLINE ARE REMAINDERS
    if ($ramMaxPercent -ge $ramCurrentPercent)
    {
        $ramOnlinePercent = ($ramOnlinePercent - $ramCurrentPercent)
        $ramMaxPercent = ($ramMaxPercent - ($ramOnlinePercent + $ramCurrentPercent))
    }
    #IF CURRENT IS BIGGER THAN MAX, MAX IS 0 AND ONLINE IS THE REMAINDER
    else
    {  
        $ramOnlinePercent = ($ramOnlinePercent - $ramCurrentPercent)
        $ramMaxPercent = 0
    }
}
else
# if($ramCurrentPercent -ge $ramOnlinePercent)
# Since current usage is higher than other metrics, the rest are set to 0
{
    $ramOnlinePercent = 0
    $ramMaxPercent = 0
}
#endregion ::: Adjust the percentages for the progress bar

#=====================
#endregion ::: RAM Calculations

#region ::: VMs
#Create the individual VM panels
Foreach ($VM in $VMs)
{
    $HardDrives = $VM.HardDrives
    $VM_style = ""
    $VM_state = ""

    [float]$VHD_Used = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].Used)/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))

    $(Switch($VM.State)
    {
        "Running" {$VM_style = "success"; $VM_state = "Online"; break;}
        "Paused" {$VM_style = "warning"; $VM_state = "Paused"; break;}
        "Off" {$VM_style = "danger"; $VM_state = "Offline"; break;}
        "Saved" {$VM_style = "warning"; $VM_state = "Paused"; break;}
        default {$VM_style = "info"; $VM_state = "Other"; break;}
    })

    $vms_string += 
@"
                    <div class="col-xs-12 col-md-12">
                        <div class="row" style="margin-bottom:5px; margin-top:5px;">
                        <div class="col-xs-3 col-md-3">
                            <button type="button" class="btn btn-$VM_style btn-block">
                            <h3 class="vmname panel-title">$($VM.Name)</h3>
                            <p class="text-center"><span class="badge">$($VM.ProcessorCount) vCPU</span></p>
                            $VM_state
                            </button>
                        </div>
                        <div class="col-xs-3 col-md-3">
                            <h4 class="text-center">RAM: $("{0:N2} GB" -f ($VM.MemoryAssigned/1gb -as [float])) of $("{0:N2} GB" -f ($VM.MemoryStartup/1gb -as [float]))</h4>
                            <div class="progress">
                                <div class="progress-bar progress-bar-striped active" role="progressbar" 
                                    aria-valuenow="$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100)) aria-valuemin="0" aria-valuemax="100" style="width:$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100))%">
                                </div>
                            </div>
                        </div>
                        
                            $(foreach($HardDrive in $HardDrives)
                            {
                                [float]$vhd_UsedPercent = ("{0:N2}" -f (($HardDrive.path | Get-VHD).FileSize/1gb –as [float])/(($HardDrive.path | Get-VHD).Size/1gb –as [float]) * 100)

                                switch ($vhd_UsedPercent)
                                {
                                    {$vhd_UsedPercent -gt 90.00} {$vhd_ProgressBar = "danger"; break}
                                    {$vhd_UsedPercent -gt 75.00} {$vhd_ProgressBar = "warning"; break}
                                    default {$vhd_ProgressBar = "success"}
                                }

                                $vhd_table += @"
                                
                                <tr>
                                    <td>$($HardDrive.path.Substring(0,1))</td>
                                    <td>$($HardDrive.ControllerLocation)</td>
                                    <td>$("{0:N2} GB" -f (($HardDrive.path | Get-VHD).FileSize/1gb –as [float]))</td>
                                    <td>$("{0:N2} GB" -f (($HardDrive.path | Get-VHD).Size/1gb –as [float]))</td>
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
                            })
                        <div class="col-xs-6 col-md-6">
                            <table class="table table-striped table-condensed text-center">
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
	.vmname {
	    text-transform: uppercase;
	    margin-bottom: 10px;
	    padding: 0;
	    text-align: center;
	}
	.row {
	    display: -webkit-box;
	    display: -webkit-flex;
	    display: -ms-flexbox;
	    display: flex;
	    flex-wrap: wrap;
	}
	.row > [class*='col-'] {
	    display: flex;
	    flex-direction: column;
	}
    th {
        text-align: center;
    }

    table .progress {
        margin-bottom: 0;
    }

    </style>
"@
#endregion ::: HEADER HTML

#region ::: BODY HTML
$body = 
@"
    <div class="container">
        <div class="jumbotron text-center"><h1 class="h1">$reportTitle</h1><h3 class="h3">$reportDate</h3><h2 class="h2 text-center">Summary</h2></div>
        <div class="row">
            <div class="col-xs-6 col-md-6">
                <div class="panel panel-info">
                    <div class="panel-heading">
                        <h3 class="vmname">Quick Stats</h3>
                    </div>
                    <div class="panel-body">
                        <p class="text-center">
                            <div class="btn-group btn-group-justified" role="group">
                                <div class="btn-group role="group">
                                <button type="button" class="btn btn-success">
                                    Online vCPUs
                                    <span class="badge">
                                    $(($VMs | Where State -eq "Running" | Measure-Object ProcessorCount -Sum).Sum)
                                    </span>
                                </button>
                                </div>
                                <div class="btn-group role="group">
                                <button type="button" class="btn btn-warning">Total vCPUs
                                    <span class="badge">
                                    $(($VMs | Measure-Object ProcessorCount -Sum).Sum)
                                    </span></button>
                                </div>
                                <div class="btn-group role="group">
                                <button type="button" class="btn btn-danger">Physical CPUs
                                    <span class="badge">
                                    $($HostProcessors.LogicalProcessorCount)
                                    </span>
                                </button>
                                </div>
                            </div>
                        </p>
                        <div class="progress">
                            <div class="progress-bar progress-bar-success" style="width:$(($runningVMs/$totalVMs)*100)%">
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
                    <div class="progress">
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
        <div class="row">
            <div class="col-xs-12 col-md-12">
                <div class="panel panel-primary">
                    <div class="panel-heading">
                        <h3 class="vmname">Hard Drives</h3>
                    </div>
                    <div class="panel-body" style="padding-top:0;padding-bottom:0;">
                        <div class="row">
                            $harddriveString
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="row">
            <div class="col-xs-12 col-md-12">
                <div class="panel panel-primary">
                    <div class="panel-heading" style="margin-bottom:20px;">
                        <h3 class="vmname">Virtual Machines</h3>
                    </div>
                    <div class="panel-body" style="padding-top:0;padding-bottom:0;">
                        <div class="row text-center">
                            <div class="col-xs-3 col-md-3"><h4>Name</h4></div>
                            <div class="col-xs-3 col-md-3"><h4>Memory</h4></div>
                            <div class="col-xs-6 col-md-6"><h4>Hard Drives</h4></div>
                            $vms_string
                        </div>
                    </div>
                </div>
            </div>
        </div>
"@

$body +=
@"
    </div>
        <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js" integrity="sha384-0mSbJDEHialfmuBBQP6A4Qrprq5OVfW37PRR3j5ELqxss1yVqOtnepnHVP9aJ7xS" crossorigin="anonymous"></script>
        <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
    </div>
"@
#endregion ::: BODY HTML

#CREATE THE HTML FILE::Defaults to C:\
ConvertTo-Html -Title $reportTitle -Head $header -Body $body | Set-Content  "C:\$reportTitle on $reportDate.htm"

#region Clear variables
rv body
rv TotalHddMax
rv TotalHddCurrent
rv TotalHddOnline
rv header
rv TotalRamMax
rv TotalRamCurrent
rv TotalRamOnline
rv hddMaxPercent 
rv hddOnlinePercent 
rv hddCurrentPercent
rv ramOnlinePercent
rv ramCurrentPercent
rv ramMaxPercent
rv harddriveString
#endregion Clear Variables

#OPEN THE HTML FILE
Invoke-Item "C:\$reportTitle on $reportDate.htm"
#BYE