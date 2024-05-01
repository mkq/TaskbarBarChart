$fgColors = ("#ffffff00", "#ff00ff00")
$bgColors = ("#70ffffff", "#5affffff")
$cmd = {
	get-WmiObject Win32_PerfFormattedData_PerfOS_Processor | where { $_.name -ne '_total' } `
	| % { [PSCustomObject] @{ name = [int]$_.name; value = [uint32]$_.PercentProcessorTime } } `
	| sort-object -property name `
	| % { [PSCustomObject] @{ name = "CPU $($_.name)"; value = $_.value } }
}

& $PSScriptRoot\..\show-taskbarBarChart -verbose -cmd $cmd -chartAndGapWidths @('15,-1,-1,15') -barWidth 15 -bgColors ($bgColors * 10) -fgColors ($fgColors * 10)
