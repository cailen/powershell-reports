#region Variables
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
$reportTitle = "VM Report for $((Get-VMHost).Name)"
$reportDate = "$(Get-Date -Format "MM-dd-yyyy")"
$driveLetters = gdr -PSProvider 'FileSystem' | Select Name, Used, Free
$VHDs = $VMs | Get-VMHardDiskDrive | Get-VHD | Select Path, FileSize, Size
$driveArrCurrent = New-Object 'System.Collections.Generic.Dictionary[string,double]'
$driveArrOnline = New-Object 'System.Collections.Generic.Dictionary[string,double]'
$driveArrMax = New-Object 'System.Collections.Generic.Dictionary[string,double]'
$driveArrUsed = @{}
$driveArrFree = @{}
$hddContainer = "info"
$hddUsedProgressBar = "success"

#endregion Variables

#region Building the VHD-to-Disk Array
#Building a dictionary for the Drives

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

#endregion

Foreach ($VM in $VMs)
{
    $TotalRamMax += $VM.MemoryStartup
    $TotalRamCurrent += $VM.MemoryAssigned
    
    if($VM.State -eq "Running")
    {
        $TotalRamOnline += $VM.MemoryStartup
    } 
}

#FUNCTION::Add the ability for ConvertTo-HTML table to modify table HTML syntax
Function Add-HTMLTableAttribute
{
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]
        $HTML,

        [Parameter(Mandatory=$true)]
        [string]
        $AttributeName,

        [Parameter(Mandatory=$true)]
        [string]
        $Value

    )


    $xml=[xml]$HTML
    $attr=$xml.CreateAttribute($AttributeName)
    $attr.Value=$Value
    $xml.table.Attributes.Append($attr) | Out-Null
    Return ($xml.OuterXML | out-string)
}

#region ::HDD Progress Bar Calculations
#=============================

foreach ($driveFor in $driveArrMax.GetEnumerator())
{
    
    $HostDriveTotal = ($driveArrFree[$driveFor.Key].Free + $driveArrUsed[$driveFor.Key].Used)

    [float]$hddMaxPercent = ("{0:N2}" -f ((($driveArrMax.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddUsedPercent = ("{0:N2}" -f ((($driveArrUsed[$driveFor.Key].Used)/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddOnlinePercent = ("{0:N2}" -f ((($driveArrOnline.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddCurrentPercent = ("{0:N2}" -f ((($driveArrCurrent.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))

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

    $harddriveString += 
@"
                            <div class="col-xs-6 col-md-6 bg-$hddContainer" style="outline: 1px solid orange;">
                                <h4 class="vmname">Hard Drive `($($driveFor.Key)`:) Usage $hddGlyph</h4>
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
                                <table class="table table-striped table-condensed text-center">
                                    <tr>
                                        <th>Drive Used Space</th>
                                        <th>Drive Free Space</th>
                                        <th>System Capacity</th>
                                    </tr>
                                    <tr>
                                        <td>$("{0:N2}" -f (($driveArrFree[$driveFor.Key].Free)/1gb -as [float]))</td>
                                        <td>$("{0:N2}" -f (($driveArrUsed[$driveFor.Key].Used)/1gb -as [float]))</td>
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
"@
}

#=====================
#endregion ::HDD Calculations

#region ::RAM Progress Bar Calculations
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

#=====================
#endregion ::RAM Calculations

#region HEADER HTML
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
</style>
"@
#endregion HEADER HTML
#region BODY HTML
$body = 
@"
    <div class="container">
        <div class="jumbotron text-center"><h1>$reportTitle</h1><h2>$reportDate</h2></div>
        <div class="page-header text-center"><h1>Summary<h1></div>
        <div class="row">
            <div class="col-xs-6 col-md-6">
                <p class="text-center">
                    Online vCPUs
                    <span class="badge">
                        $(($VMs | Where State -eq "Running" | Measure-Object ProcessorCount -Sum).Sum)
                    </span>
                     Total vCPUs
                    <span class="badge">
                        $(($VMs | Measure-Object ProcessorCount -Sum).Sum)
                    </span>
                     Host Logical Processors
                    <span class="badge">
                        $($HostProcessors.LogicalProcessorCount)
                    </span>
                </p>
            </div>
            <div class="col-xs-6 col-md-6">
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
        <div class="row">
            <div class="col-xs-12 col-md-12">
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
                    <div class="panel-body" style="padding-top:0;padding-bottom:0">
                        <div class="row">
                            $harddriveString
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="page-header text-center"><h1>Virtual Machine Details<h1></div>
        <div class="row">
"@

Foreach ($VM in $VMs)
{
    $HardDrives = $VM.HardDrives

    $body += 
@"
            <div class="col-xs-6 col-md-4">
                <div class="panel panel-primary">
                    <div class="panel-heading">
                        <h3 class="vmname panel-title">$($VM.Name)</h3>
                        <p class="text-center"><span class="badge">$($VM.ProcessorCount) vCPU</span></p>
                    </div>
                    <div class="panel-body">
                        $(Switch($VM.State)
                        {
                            "Running" {'<button type="button" class="btn btn-success btn-block">Online</button>'; break;}
                            "Paused" {'<button type="button" class="btn btn-warning btn-block">Paused</button>'; break;}
                            "Off" {'<button type="button" class="btn btn-danger btn-block">Offline</button>'; break;}
                            "Saved" {'<button type="button" class="btn btn-warning btn-block">Saved</button>'; break;}
                            default {'<button type="button" class="btn btn-info btn-block">Other</button>'; break;}
                        })
                        <h4 class="text-center">RAM: $("{0:N2} GB" -f ($VM.MemoryAssigned/1gb -as [float])) of $("{0:N2} GB" -f ($VM.MemoryStartup/1gb -as [float]))</h4>
                        <div class="progress">
                            <div class="progress-bar progress-bar-striped active" role="progressbar" 
                                aria-valuenow="$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100)) aria-valuemin="0" aria-valuemax="100" style="width:$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100))%">
                            </div>
                        </div>
                        <h4 class="text-center">Virtual Hard Drives </h4>
                    </div>
                    $($HardDrives | ConvertTo-Html -Fragment @{label=’Loc’;expression={$_.path.Substring(0,1)}},@{label=’Disk’;expression={$_.ControllerLocation}},@{label=’Current Size’;expression={("{0:N2} GB" -f (($_.path | Get-VHD).FileSize/1gb –as [float]))}}, @{label=’Max Size’;expression={("{0:N2} GB" -f (($_.path | Get-VHD).Size/1gb –as [float]))}} | out-string | Add-HTMLTableAttribute -AttributeName 'class' -Value 'table table-striped table-condensed text-center')
                </div>
            </div>
"@
}

$body +=
@"
        </div>
    </div>
        <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js" integrity="sha384-0mSbJDEHialfmuBBQP6A4Qrprq5OVfW37PRR3j5ELqxss1yVqOtnepnHVP9aJ7xS" crossorigin="anonymous"></script>
        <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
    </div>
"@
#endregion BODY HTML

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
# USED FOR TESTING HTML INTEGRITY -> ConvertTo-Html -PostContent $HTML