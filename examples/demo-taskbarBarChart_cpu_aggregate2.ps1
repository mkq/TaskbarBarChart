$cmd = {
	set-strictMode -off
	get-WmiObject Win32_PerfFormattedData_PerfOS_Processor -Property name,PercentProcessorTime `
	| where { $_.name -ne '_total' } `
	| sort-object -property PercentProcessorTime -descending `
	| %{
		if ($prev -eq $null) {
			$prev = $_
		} else {
			[PSCustomObject] @{
				name = 'CPUs {0:d2},{1:d2}' -f [int]$_.name, [int]$prev.name;
				value = [int]($_.PercentProcessorTime + $prev.PercentProcessorTime + 0.5) / 2 };
			$prev = $null
}}}

& $PSScriptRoot\..\show-taskbarBarChart -verbose -cmd $cmd
