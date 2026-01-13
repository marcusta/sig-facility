Run, C:\start\copy_gspro_settings.bat
Run, C:\GSProV1\GSPLauncher.exe
;; WinWait, GSPro Configuration
;; WinActivate, GSPro Configuration
;; Send, {Enter}

WinWait, GSPro x Foresight

WinWait, GSPro
WinWait, GSPro x Fore
WinActivate, GSPro x Foresight

WinWait, GSPro x Foresight
sleep, 400
ControlClick, x1080 y190, GSPro x Foresight, , , , , , , Text, Open Visual Data
sleep, 300

FileDelete, C:\start\application_log.txt
FileDelete, C:\start\error_log.txt

Run, C:\start\gs-checker.exe --mode Prod, c:\start,, gsCheckerPID
Run, C:\start\start-overlay.bat
;; Run, C:\start\repair-connector.ahk

WinActivate, GSPro

WinSet, Top,, GSPro
sleep, 1000
WinSet, Bottom,, GSPro x Foresight
WinActivate, GSPro
WinSet, Top,, GSPro
WinSet, Bottom,, GSPro x Foresight
WinActivate, GSPro
Loop,
{
   if (!WinExist("GSPro")) {
      WinClose, OnTopReplica
      WinClose, OnTopReplica
      if (gsCheckerPID)
         Process, Close, %gsCheckerPID%
      break
   }

   sleep, 2000 
} 


return
