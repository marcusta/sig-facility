Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.Size = New-Object System.Drawing.Size(600, 200)
$form.ShowInTaskbar = $false
$form.Text = "SimGolf-StartupOverlay"

$label = New-Object System.Windows.Forms.Label
$a = [char]0x00E4
$label.Text = "V${a}nligen v${a}nta, systemet startar..."
$label.ForeColor = [System.Drawing.Color]::White
$label.Font = New-Object System.Drawing.Font("Segoe UI", 24)
$label.AutoSize = $false
$label.Size = $form.ClientSize
$label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

# Write PID so the launcher can kill us reliably
$PID | Set-Content "C:\SimGolf\overlay.pid" -Force

$form.Controls.Add($label)
$form.ShowDialog()
