$cmd = {
	get-WmiObject Win32_PerfFormattedData_PerfOS_Processor -Property name,PercentProcessorTime `
	| % { [PSCustomObject] @{
		name = if($_.name -match '^\d+$') { "CPU $('{0:d2}' -f [int]$_.name)" } else { $_.name -ireplace '^[^a-z]+', '' };
		value = $_.PercentProcessorTime } } `
	| sort-object -property name
}

& $PSScriptRoot\..\show-taskbarBarChart -verbose -cmd $cmd
