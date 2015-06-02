@ECHO OFF
"D:\Program Files\AvrAssembler2\avrasm2.exe" -S "D:\programs\Project\labels.tmp" -fI -W+ie -C V3 -o "D:\programs\Project\Project.hex" -d "D:\programs\Project\Project.obj" -e "D:\programs\Project\Project.eep" -m "D:\programs\Project\Project.map" "D:\programs\Project\Project.asm"
