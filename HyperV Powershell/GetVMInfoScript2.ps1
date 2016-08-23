#region Variables
$TotalHddMax = 0.00
$TotalHddCurrent = 0.00
$TotalHddOnline = 0.00
$TotalRamMax = 0.00
$TotalRamCurrent = 0.00
$TotalRamOnline = 0.00
$HostMemory = Get-VMHost | Select MemoryCapacity
$VMs = Get-VM
$runningVMs = ($VMs | Where State -eq "Running" | Measure).Count
$pausedVMs = ($VMs | Where State -eq "Paused" | Measure).Count
$offlineVMs = ($VMs | Where State -eq "Off" | Measure).Count
$totalVMs = ($VMs).Count
$reportTitle = "VM Report for $((Get-VMHost).Name)"
$reportDate = "$(Get-Date -Format "MM-dd-yyyy")"
$driveLetters = gdr -PSProvider 'FileSystem' | Select Name, Used, Free
$VHDs = $VMs | Get-VMHardDiskDrive | Get-VHD | Select Path, FileSize, Size
$driveArrCurrent = @{}
$driveArrOnline = @{}
$driveArrMax = New-Object 'System.Collections.Generic.Dictionary[string,double]'
$driveArrUsed = @{}
$driveArrFree = @{}
$hddContainer = "info"
$harddriveString = ""
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

#region ::HDD Progress Bar Calculations
#=============================

foreach ($driveFor in $driveArrMax.GetEnumerator())
{
    $HostDriveTotal = ($driveArrFree[$driveFor.Key].Free + $driveArrUsed[$driveFor.Key].Used)

    [float]$hddMaxPercent = ("{0:N2}" -f ((($driveArrMax.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddOnlinePercent = ("{0:N2}" -f ((($driveArrOnline.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))
    [float]$hddCurrentPercent = ("{0:N2}" -f ((($driveArrCurrent.Get_Item($driveFor.Key))/1gb -as [float])/($HostDriveTotal/1gb -as [float]) * 100))

    if($hddMaxPercent -gt 100){$hddMaxPercent = 100.00;}
    if($hddCurrentPercent -gt 100)
    {
        $hddCurrentPercent = 100.00 
        $hddContainer = "danger"
    }
    if($hddOnlinePercent -ge 100)
    {
        $hddOnlinePercent = 100.00
        $hddContainer = "danger"
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
                <div class="panel panel-$hddContainer">
                    <div class="panel-heading">
                        <h2 class="vmname">Hard Drive `($($driveFor.Key)`:) Usage</h2>
                    </div>
                    <div class="panel-body">
                        <h3 class="text-center">Current Disk Use: $("{0:N2}" -f (($driveArrCurrent.Get_Item($driveFor.Key))/1gb -as [float]))/$("{0:N2} GB" -f ($HostDriveTotal/1gb -as [float]))</h3>
                        <h3 class="text-center">Running Disk Max: $("{0:N2}" -f (($driveArrOnline.Get_Item($driveFor.Key))/1gb -as [float]))/$("{0:N2} GB" -f ($HostDriveTotal/1gb -as [float]))</h3>
                        <h3 class="text-center">Total Disk Max: $("{0:N2}" -f (($driveArrMax.Get_Item($driveFor.Key))/1gb -as [float]))/$("{0:N2} GB" -f ($HostDriveTotal/1gb -as [float]))</h3>
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
                </div>
"@

    $hddcontainer = "info"
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

#region HEADER HTML
$header = 
@"
<title>$reportTitle on $reportDate</title>
<link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css" integrity="sha384-1q8mTJOASx8j1Au+a5WDVnPi2lkFfwwEAa8hDDdjZlpLegxhjVME1fgjWPGmkzs7" crossorigin="anonymous">
<link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap-theme.min.css" integrity="sha384-fLW2N01lMqjakBkx3l/M9EahuwpSfeNvV63J5ezn3uZzapT0u7EYsXMjQV+0En5r" crossorigin="anonymous">
<style type="text/css">
	body {
		font-family: Segoe, "Segoe UI", "DejaVu Sans", "Trebuchet MS", Verdana, sans-serif;
	}
	.vmname {
	    text-transform: uppercase;
	    font-weight: normal;
	    margin-bottom: 10px;
	    padding: 0;
	    text-align: center;
	}
	    body div h3 {
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
</style>
"@
#endregion HEADER HTML
#region BODY HTML
$body = 
@"
    <div class="container">
        <div class="jumbotron text-center"><h1>$reportTitle</h1><h2>$reportDate</h2></div>
        <div class="page-header text-center"><h1>Summary<h1></div>
        <div class="progress">
            <div class="progress-bar progress-bar-success" style="width:$(($runningVMs/$totalVMs)*100)%">
                <span>$runningVMs Online</span>
                    </div>
            <div class="progress-bar progress-bar-warning progress-bar-striped" style="width:$(($pausedVMs/$totalVMs)*100)%">
                <span>$pausedVMs Paused</span>
            </div>
            <div class="progress-bar progress-bar-danger" style="width:$(($offlineVMs/$totalVMs)*100)%">
                <span>$offlineVMs Offline</span>
            </div>
        </div>
        <div class="row">
            <div class="col-xs-6 col-md-6">
                <div class="panel panel-$memoryOnlineProgressBar">
                    <div class="panel-heading">
                        <h2 class="vmname">Memory Usage</h2>
                    </div>
                    <div class="panel-body">
                        <h3 class="text-center">Current Memory Use: $("{0:N2}" -f ($TotalRamCurrent/1gb -as [float]))/$("{0:N2} GB" -f ($HostMemory.MemoryCapacity/1gb -as [float]))</h3>
                        <h3 class="text-center">Running Memory Max: $("{0:N2}" -f ($TotalRamOnline/1gb -as [float]))/$("{0:N2} GB" -f ($HostMemory.MemoryCapacity/1gb -as [float]))</h3>
                        <h3 class="text-center">Total Memory Max: $("{0:N2}" -f ($TotalRamMax/1gb -as [float]))/$("{0:N2} GB" -f ($HostMemory.MemoryCapacity/1gb -as [float]))</h3>
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
            <div class="col-xs-6 col-md-6">
                $harddriveString
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
                        <h2 class="vmname">$($VM.Name)</h2>
                    </div>
                    <div class="panel-body">
                        $(Switch($VM.State)
                        {
                            "Running" {'<button type="button" class="btn btn-success btn-block">Online</button>'; break;}
                            "Paused" {'<button type="button" class="btn btn-warning btn-block">Paused</button>'; break;}
                            "Off" {'<button type="button" class="btn btn-danger btn-block">Offline</button>'; break;}
                            default {'<button type="button" class="btn btn-info btn-block">Other</button>'; break;}
                        })
                        <h3 class="text-center">RAM: $("{0:N2} GB" -f ($VM.MemoryAssigned/1gb -as [float])) of $("{0:N2} GB" -f ($VM.MemoryStartup/1gb -as [float]))</h3>
                        <div class="progress">
                            <div class="progress-bar progress-bar-striped active" role="progressbar" 
                                aria-valuenow="$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100)) aria-valuemin="0" aria-valuemax="100" style="width:$("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100))%">
                            </div>
                        </div>
                        <h3 class="text-center">Virtual Hard Drives </h3>
                        $($HardDrives | ConvertTo-Html -Fragment @{label=’Disk’;expression={$_.ControllerLocation}},@{label=’Current Size’;expression={("{0:N2} GB" -f (($_.path | Get-VHD).FileSize/1gb –as [float]))}}, @{label=’Max Size’;expression={("{0:N2} GB" -f (($_.path | Get-VHD).Size/1gb –as [float]))}} | out-string | Add-HTMLTableAttribute -AttributeName 'class' -Value 'table table-striped table-bordered')
                    </div>
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

#REMOVE the variables
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

#OPEN THE HTML FILE
Invoke-Item "C:\$reportTitle on $reportDate.htm"
#BYE
# USED FOR TESTING HTML INTEGRITY -> ConvertTo-Html -PostContent $HTML