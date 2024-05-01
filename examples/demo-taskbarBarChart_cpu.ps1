$cmd = {
	get-WmiObject Win32_PerfFormattedData_PerfOS_Processor | where { $_.name -ne '_total' } `
	| % { [PSCustomObject] @{ name = [int]$_.name; value = [uint32]$_.PercentProcessorTime } } `
	| sort-object -property name `
	| % { [PSCustomObject] @{ name = "CPU $($_.name)"; value = $_.value } }
}

& $PSScriptRoot\..\show-taskbarBarChart -verbose -cmd $cmd
