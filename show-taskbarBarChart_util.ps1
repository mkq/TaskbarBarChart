# A value plus presentation stuff
class StyledValue {
	[string] $name
	[uint32] $value
	$color = $null

	[string] toString() {
		$colorStr = if ($null -eq $this.color) { '' } else { ", color $($this.color)" }
		return 'StyledValue("{0}": {1}{2})' -f $this.name, $this.value, $colorStr
	}

	[string] tooltipText() {
		return '{0}: {1}' -f $this.name, $this.value
	}
}

# A list of StyledValue representing their history
class HistStyledValue {
	static [StyledValue] $defaultValue = (new-object StyledValue -property @{ name = '-'; value = 0; })

	# head = newest
	[System.Collections.Generic.LinkedList[StyledValue]] $values = (new-object System.Collections.Generic.LinkedList[StyledValue])

	[void] setSize([uint32] $size) {
		while ($this.values.count -gt $size) { $this.values.removeLast() }
		while ($this.values.count -lt $size) { $this.values.addLast([HistStyledValue]::defaultValue) }
	}

	[void] add([StyledValue] $styledValue) {
		$this.values.removeLast();
		$this.values.addFirst($styledValue);
	}

	[string] toString() { return $this.values.toString(); }
}

# dimensions of a single chart
# E.g. for an element '-1,15,-1,7,-1,7' in $chartAndGapWidths, there are three Charts:
# [offset: 1, width: 15], [offset: 17, width: 7], [offset: 25, width: 7]
class ChartLocation {
	ChartLocation() {}
	[uint32] $offset
	[uint32] $width
	[string] toString() { return "(offset: $($this.offset), width: $($this.width))" }
}

class IconLayout {
	IconLayout() { $this.width = 0; $this.chartLocations = @(); }
	[uint32] $width #including gaps
	[ChartLocation[]] $chartLocations
	[string] toString() { return "IconLayout($($this.width), $($this.chartLocations | %{$_.toString()} | join ', '))" }
}

# cmdlet alternative for -join operator => fewer parentheses needed
function join {
	param(
		[string] $separator = '',
		[string] $prefix = '',
		[string] $suffix = '',
		[Parameter(ValueFromPipeline = $true)] $pipeArg
	)
	begin { $tmpSep = ''; $result = '' }
	process {
		$result += $tmpSep
		$result += $pipeArg
		$tmpSep = $separator
	}
	end { $result }
}

function getProperty {
	param($object, [string[]] $property, $default = $null)
	foreach ($pr in $property) {
		try {
			$value = $null
			invoke-expression "`$value = `$object.$pr"
			if ($value -ne $null) { write-debug "getProperty(.., $property) == $value"; return $value }
		} catch {}
	}
	write-debug "getProperty(.., $property) == $default"
	return $default
}

function arrayElementAtOrDefault {
	param([object[]] $array, [int] $index, $defaultValue = $null)
	$result = if ($index -ge 0 -and $index -lt $array.length) { $array[$index] } else { $defaultValue }
	write-debug ('arrayElementAtOrDefault(.., {0}) == {1}' -f $index, $result.toString())
	$result
}

function arrayElementAtOrLast {
	param([object[]] $array, [int] $index, [string] $comment = '')
	if ($comment -ne '') { $comment += ': ' }
	$result = $array[[System.Math]::min($index, $array.length - 1)]
	write-debug ('{0}arrayElementAtOrLast(.., {1}) == {2}' -f $comment, $index, $result.toString())
	$result
}
