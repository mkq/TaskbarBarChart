'process {0} startet on {1}' -f ($pid, (get-date))
''
get-content $MyInvocation.MyCommand.Path
$dir = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$parentDir = (Split-Path -Parent $dir)
$fgColors = ("#ffff0000", "#ff00ff00")
$bgColors = ("#40ffffff", "#30ffffff")
& "$parentDir\show-taskbarBarChart.ps1" -interval 1000 -barWidth 6 -chartAndGapWidths "30,-2,-2,30" -bgColors ($bgColors * 8) -fgColors ($fgColors * 8)
