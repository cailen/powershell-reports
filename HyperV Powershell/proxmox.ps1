[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
Remove-Variable session

#$servername = Read-Host -Prompt 'What is the server IP?'
$servername = "209.208.48.68"
#$uri = 'https://'+$servername+':8006/api2/json/'
$uri = 'https://209.208.48.68:8006/api2/json'

$ticketuri = $uri+'access/ticket'
$C = Get-Credential -Message 'Enter the server login'

#$ticket = Invoke-RestMethod -Method Post -uri $ticketuri -body ('username='+$C.UserName+'@pam&password='+$C.GetNetworkCredential().Password) -Verbose
#$ticket = Invoke-WebRequest -Method Post -uri $ticketuri -Credential $C -Verbose
$ticket = Invoke-RestMethod -Method Post -uri $ticketuri -body ('username=root@pam&password=Nrprocks!') -Verbose

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$cookie = New-Object System.Net.Cookie    
$cookie.Name = "PVEAuthCookie"
$cookie.Value = $ticket.data.ticket
$cookie.Domain = $servername
$session.Cookies.Add($cookie);

$results = Invoke-RestMethod -uri ($uri+'nodes/') -WebSession $session -Verbose
$results2 = Invoke-RestMethod -uri ($uri+'nodes/300-2058/qemu') -WebSession $session -Verbose
#$node = $results.data.node
#$results = Invoke-RestMethod -uri ($uri+'nodes/'+$node+'/lxc') -WebSession $session -Verbose
$results

##Need to check that there is just one NODE
$results.data.Count

$results.data.node