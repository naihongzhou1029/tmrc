args! project.vim
argadd **/*.md
argadd devops.ps1
rightbelow vert term powershell -NoExit -Command "Start-Sleep -Seconds 1; agent"
