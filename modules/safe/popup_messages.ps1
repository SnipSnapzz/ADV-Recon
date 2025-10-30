<#
.SYNOPSIS
    Shows popup messages
.DESCRIPTION
    This module is completely safe. Shows popups with predefined messages that you can customize.
#>

function Show-PopupMessages {
    param(
        [int]$Cycles = 3
    )

    Add-Type -AssemblyName System.Windows.Forms

    $msgs = @(
        "This is a pseudo-malicious popup message frfr",
        "hello",
        "Im in your puter (not really its just a pop up)"
    )

    for ($i = 1; $i -le $Cycles; $i++) {
        foreach ($msg in $msgs) {
            [System.Windows.Forms.MessageBox]::Show($msg, "Demo Popup", 0, 'Information')
        }
    }
}