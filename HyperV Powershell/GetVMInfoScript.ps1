﻿$nl = [Environment]::NewLine
$TotalHddAssigned
$TotalHddCurrent
$TotalRamUsed
$HostMemory = (Get-VMHost).MemoryCapacity
$arrayMemory = @()

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

$reportTitle = "VM Report for $((Get-VMHost).Name)"
$reportDate = "$(Get-Date -Format "MM-dd-yyyy")"

$header += "<title>$reportTitle on $reportDate</title>" + $nl
$header += @'
<link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css" integrity="sha384-1q8mTJOASx8j1Au+a5WDVnPi2lkFfwwEAa8hDDdjZlpLegxhjVME1fgjWPGmkzs7" crossorigin="anonymous">
<link rel="stylesheet" type="text/css" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap-theme.min.css" integrity="sha384-fLW2N01lMqjakBkx3l/M9EahuwpSfeNvV63J5ezn3uZzapT0u7EYsXMjQV+0En5r" crossorigin="anonymous">
<style type="text/css">
	body {
		font-family: Segoe, "Segoe UI", "DejaVu Sans", "Trebuchet MS", Verdana, sans-serif;
	}
	.total {
		padding: 0;
		margin: 0;
		text-transform: uppercase;
		color: #3377FF;
		background-color: #E7E7E7;
		text-align: center;
	}
	.title {
	text-align: center;
	text-transform: uppercase;
	background-color: #3377FF;
	margin-top: 25px;
	padding-top: 0px;
	margin-bottom: 0px;
	color: #E7E7E7;
	font-weight: normal;
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
	.ram {
		margin-top: 0;
		margin-right: 0;
		margin-left: 0px;
		margin-bottom: 0;
		padding: 0;
		color: #F89A00;
		font-variant: normal;
		font-weight: 500;
		font-size: large;
	}
	.hdd {
		margin-top: 0;
		margin-right: 0;
		margin-left: 0;
		margin-bottom: 0;
		color: #3377FF;
		font-size: large;
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
    .ramtotal {
	    color:#F89A00;
    }
</style>
'@

$VMs = Get-VM
Foreach ($VM in $VMs)
{
    $TotalRamUsed += $VM.MemoryStartup

    $HardDrives = $VM.HardDrives
    Foreach ($HardDrive in $HardDrives)
    {   
        $TotalHddAssigned += ($HardDrive.path | Get-VHD).Size
        $TotalHddCurrent += ($HardDrive.path | Get-VHD).FileSize
    }
}

$ramPercent = ("{0:N2}" -f (($TotalRamUsed/1gb -as [float])/($HostMemory/1gb -as [float]) * 100))

switch ($ramPercent)
        {
            {$_ -gt 90.00} {$memoryProgressBar = "danger"; break}
            {$_ -gt 75.00} {$memoryProgressBar = "warning"; break}
            default {$memoryProgressBar = "success"}
        }

$report += $nl + '<div class="container">'
$report += $nl + '<div class="jumbotron text-center"><h1>' + $reportTitle + "</h1><h2>$reportDate</h2></div>"
$report += $nl + '<div class="page-header text-center"><h1>Summary<h1></div>'

$runningVMs = ($VMs | Where State -eq "Running" | Measure).Count
$pausedVMs = ($VMs | Where State -eq "Paused" | Measure).Count
$offlineVMs = ($VMs | Where State -eq "Off" | Measure).Count
$totalVMs = ($VMs).Count

$report += $nl + '<div class="progress">
  <div class="progress-bar progress-bar-success" style="width:' + ($runningVMs/$totalVMs)*100 + '%">
    <span>' + $runningVMs + '</span>
  </div>
  <div class="progress-bar progress-bar-warning progress-bar-striped" style="width: ' + ($pausedVMs/$totalVMs)*100 + '%">
    <span>' + $pausedVMs + '</span>
  </div>
  <div class="progress-bar progress-bar-danger" style="width: ' + ($offlineVMs/$totalVMs)*100 + '%">
    <span>' + $offlineVMs + '</span>
  </div>
</div>'

$report += $nl + '<div class="row">'
$report += $nl + '<div class="col-xs-6 col-md-6">'
    $report += $nl + '<div class="panel panel-' + $memoryProgressBar + '">'
    $report += $nl + '<div class="panel-heading">'
    $report += $nl + '<h2 class="vmname">Memory Usage</h2>'
    $report += $nl + '</div>'

    $report += $nl + '<div class="panel-body">'

        $report += '<h3 class="text-center">' + ("{0:N2}" -f ($TotalRamUsed/1gb -as [float])) + " GB"
        $report += " out of " + ("{0:N2} GB" -f ($HostMemory/1gb -as [float])) + "</h3>"

        $report += $nl + '<div class="progress">
            <div class="progress-bar progress-bar-' + $memoryProgressBar + ' progress-bar-striped active" role="progressbar" 
            aria-valuenow="' + ("{0:N2}" -f (($TotalRamUsed/1gb -as [float])/($HostMemory/1gb -as [float]) * 100)) + '" aria-valuemin="0" aria-valuemax="100" style="width:' + ("{0:N2}" -f (($TotalRamUsed/1gb -as [float])/($HostMemory/1gb -as [float]) * 100)) + '%">
            </div>
            </div>'
        $report += $nl + "</div>"
    $report += $nl + "</div>"
$report += $nl + "</div>"

    $report += $nl + '<div class="col-xs-6 col-md-6">'
    $report += $nl + '<div class="panel panel-info">'
    $report += $nl + '<div class="panel-heading">'
    $report += $nl + '<h2 class="vmname">Hard Drive Usage</h2>'
    $report += $nl + '</div>'

    $report += $nl + '<div class="panel-body">'

        $report += $nl + '<h3 class="text-center">Total HDD Allocated: '
        $report += ("{0:N2}" -f ($TotalHddAssigned/1gb -as [float])) + " GB </h3>"

        $report += $nl + '<h3 class="text-center">Current HDD Allocated: '
        $report += ("{0:N2}" -f ($TotalHddCurrent/1gb -as [float])) + " GB </h3>"

    $report += $nl + "</div>"
$report += $nl + "</div>"
 $report += $nl + "</div>"
$report += $nl + "</div>"

$report += $nl + '<div class="page-header text-center"><h1>Virtual Machine Details<h1></div>'

$report += $nl + '<div class="row">'

Foreach ($VM in $VMs)
{
    $report += $nl + '<div class="col-xs-6 col-md-4">'
    $report += $nl + '<div class="panel panel-primary">'
    $report += $nl + '<div class="panel-heading">'
    $report += $nl + '<h2 class="vmname">' + $($Vm.Name) + "</h2>"
    $report += $nl + '</div>'

    $report += $nl + '<div class="panel-body">'

    Switch($VM.State)
    {
        "Running" {$report += $nl + '<button type="button" class="btn btn-success btn-block">Online</button>'}
        "Paused" {$report += $nl + '<button type="button" class="btn btn-warning btn-block">Paused</button>'}
        "Off" {$report += $nl + '<button type="button" class="btn btn-danger btn-block">Offline</button>'}
        default {$report += $nl + '<button type="button" class="btn btn-info btn-block">Other</button>'}
    }

    $report += $nl + '<h3 class="text-center">RAM: ' + ("{0:N2} GB" -f ($VM.MemoryAssigned/1gb -as [float])) + " of " + ("{0:N2} GB" -f ($VM.MemoryStartup/1gb -as [float])) + "</h3>"

    $report += $nl + '<div class="progress">
                      <div class="progress-bar progress-bar-striped active" role="progressbar" 
                      aria-valuenow="' + ("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100)) + '" aria-valuemin="0" aria-valuemax="100" style="width:' + ("{0:N2}" -f (($VM.MemoryAssigned/1gb -as [float])/($VM.MemoryStartup/1gb -as [float]) * 100)) + '%">
                      </div>
                      </div>'


    $TotalRamUsed += $VM.MemoryStartup

    $HardDrives = $VM.HardDrives
    $report += $nl + '<h3 class="text-center">Virtual Hard Drives </h3>'

    $report += $HardDrives | ConvertTo-Html -Fragment @{label=’Disk’;expression={$_.ControllerLocation}},@{label=’Current Size’;expression={("{0:N2} GB" -f (($_.path | Get-VHD).FileSize/1gb –as [float]))}}, @{label=’Max Size’;expression={("{0:N2} GB" -f (($_.path | Get-VHD).Size/1gb –as [float]))}} | out-string | Add-HTMLTableAttribute -AttributeName 'class' -Value 'table table-striped table-bordered'
    
    Foreach ($HardDrive in $HardDrives)
    {   
        $TotalHddAssigned += ($HardDrive.path | Get-VHD).Size
        $TotalHddCurrent += ($HardDrive.path | Get-VHD).FileSize
    }
    
    $report += $nl + '</div>'
    $report += $nl + '</div>'
    $report += $nl + '</div>'
}

$report += $nl + '</div>'

$postContent = '<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js" integrity="sha384-0mSbJDEHialfmuBBQP6A4Qrprq5OVfW37PRR3j5ELqxss1yVqOtnepnHVP9aJ7xS" crossorigin="anonymous"></script>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script></div>'

$HTMLtest = ConvertTo-Html -Title $reportTitle -Head $header -Body $report -PostContent $postContent | Set-Content  "C:\$reportTitle on $reportDate.htm"

rv report
rv TotalRamUsed
rv TotalHddAssigned
rv TotalHddCurrent
rv header

Invoke-Item "C:\$reportTitle on $reportDate.htm"
