Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

if (-not ($(scoop -v))) {
    Invoke-RestMethod get.scoop.sh | Invoke-Expression
}

scoop install git

git clone https://github.com/mikalauskas/.restic.git $($env:PUBLIC)\.restic

If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$($env:PUBLIC)\.restic\install.ps1`"" -Verb RunAs
    Exit
}