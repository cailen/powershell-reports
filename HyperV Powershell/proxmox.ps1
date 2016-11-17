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

$nodes = Invoke-RestMethod -uri ($uri+'nodes/') -WebSession $session -Verbose

foreach ($node in $nodes.data) {
    $qemus = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/qemu') -WebSession $session -Verbose
    foreach ($qemu in $qemus.data) {
        #will need to popular the {storage} name since it won't always be local
        $content = Invoke-RestMethod -uri ($uri+'nodes/'+$node.node+'/storage/local/content') -WebSession $session -Verbose
        foreach ($item in $content.data) {
            if ($item.content -eq "images") {
                if($item.vmid -eq $qemu.vmid)
                {
                    $item
                }
            }
        }
    }
}
    

Remove-Variable session