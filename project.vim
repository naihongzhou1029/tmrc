args! project.vim
argadd **/*.md
argadd devops.sh
rightbelow vert term powershell -NoExit -Command "Start-Sleep -Seconds 1; agent"
