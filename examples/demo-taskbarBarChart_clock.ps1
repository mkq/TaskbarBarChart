$cmd = {
	$date = get-date
	[PSCustomObject[]] @(
		@{ name = 'hour';   value = $date.hour % 12 },
		@{ name = 'minute'; value = $date.minute },
		@{ name = 'second'; value = $date.second } )
}
$parentDir = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))

& $parentDir\show-taskbarBarChart -verbose -debugOutput -cmd $cmd -maxValues @(23, 59, 59) -interval 1000 `
	-chartAndGapWidths @('-1,4,-1,4,-1,4,-1') -barwidth 4 -fgColors @('red', '#ff9000', '#efefef')
