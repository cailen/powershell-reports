$VMs = Get-VM
$VHDs = $VMs | Get-VMHardDiskDrive | Get-VHD # | Select Path, FileSize, Size
$filesystems = gdr -PSProvider 'FileSystem' | Select Name
$driveArr = @{}

foreach($driveLetter in $filesystems)
{
    foreach($VHD in $VHDs)
    {
        if($VHD.Path.StartsWith($driveLetter.Name))
        {
            if($driveArr.ContainsKey($driveLetter.Name))
            {
                
            }
            else
            {
                
            }
        }
    } 
}

Foreach ($VM in $VMs)
{
    $TotalRamMax += $VM.MemoryStartup
    $TotalRamCurrent += $VM.MemoryAssigned
    
    if($VM.State -eq "Running")
    {
        $TotalRamOnline += $VM.MemoryStartup
    } 

    $HardDrives = $VM.HardDrives
    
    Foreach ($HardDrive in $HardDrives)
    {   
        $TotalHddMax += ($HardDrive.path | Get-VHD).Size
        $TotalHddCurrent += ($HardDrive.path | Get-VHD).FileSize
        
        $HardDrive.Path

        if($HardDrive.Path.StartsWith("C:"))
        {
            $temptemp = "YES"
        }
        else
        {
            $temptemp = "NO"
        }
        
        
        if($VM.State -eq "Running")
        {
            $TotalHddOnline += ($HardDrive.path | Get-VHD).Size
            
        } 
    }

    Write-Verbose $temptemp -verbose
}