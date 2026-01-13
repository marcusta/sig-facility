GSPStarted := false ; Initialize the variable as false

Loop
{
    ; Sleep for 2 seconds
    Sleep, 2000

    if (!WinExist("GSPro"))
    {
        ; If it does not exist, break out of the loop
        WinClose, OnTopReplica
        WinClose, OnTopReplica
        break
    }

    ; Check if neither window exists
    if (!WinExist("GSPro x Foresight")) 
    {
        sleep, 2000
        if (!WinExist("GSPro"))
        {
            ; If it does not exist, break out of the loop
            WinClose, OnTopReplica
            WinClose, OnTopReplica
            break
        }
        sleep, 1000
        if (!WinExist("GSPro x Foresight")) 
        {
            ; Start the GSPconnect.exe program
            Run, C:\GSProV1\Core\GSPC\GSPconnect.exe
            GSPStarted := true ; Set the variable when GSPConnect.exe is run
            WinClose, OnTopReplica
            WinClose, OnTopReplica

            sleep, 1000
            ; Wait for one of the windows to appear
            WinWait, GSPro x Foresight
            ControlClick, x1059 y182, GSPro x Foresight, , , , , , , Text, Open Visual Data
        }
    }

    ; If "APIv1 Connect" exists, just continue the loop
    if (WinExist("GSPro x Foresight") && GSPStarted)
    {
        Run, C:\start\start-overlay.bat
        GSPStarted := false ; Reset the variable
    }
}
