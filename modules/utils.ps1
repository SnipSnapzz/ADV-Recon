function Get-RegistryValue {
    param($Key, $Value)
    (Get-ItemProperty $Key $Value).$Value
}

function Get-GeoLocation {
    try {
        Add-Type -AssemblyName System.Device
        $GeoWatcher = New-Object System.Device.Location.GeoCoordinateWatcher
        $GeoWatcher.Start()
        while (($GeoWatcher.Status -ne 'Ready') -and ($GeoWatcher.Permission -ne 'Denied')) { Start-Sleep -Milliseconds 100 }
        if ($GeoWatcher.Permission -eq 'Denied') { return "Denied" }
        else { $GeoWatcher.Position.Location | Select-Object Latitude, Longitude }
    } catch { return "No Coordinates Found" }
}
