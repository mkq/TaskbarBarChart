# Copyright (c) 2021 mkq
# SPDX-License-Identifier: MIT

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
	[uint32] $offset # x start coordinate within icon; not including the gap
	[uint32] $width # not including the gap
	[uint32] $leftGapWidth
	[uint32] $rightGapWidth
	[string] toString() { return "(offset: $($this.offset), width: $($this.width), gap: $($this.leftGapWidth)|$($this.rightGapWidth))" }
}

class IconLayout {
	IconLayout([string] $iconLayoutStr, [uint32] $defaultWidth) {
		# first loop: replace charts with ChartLocation objects without gapWidths
		$xOffset = 0
		$foundChart = $false
		$tmpChartLocationsAndGaps = @() # with positive gap widths
		foreach ($part in $iconLayoutStr -split '\s*,\s*') {
			if ($part -match '^\s*$') { $part = $defaultWidth }
			$part = [int] $part
			if ($part -lt 0) { # gap
				$xOffset -= $part
				$tmpChartLocationsAndGaps += @(-$part)
			} elseif ($part -gt 0) { # chart
				$foundChart = $true
				$chartLocation = [ChartLocation] @{ width = $part; offset = $xOffset; leftGapWidth = 0; rightGapWidth = 0 }
				write-debug "new ChartLocation: $($chartLocation.toString())"
				$xOffset += $part
				$tmpChartLocationsAndGaps += @($chartLocation)
			} else {
				throw "invalid zero in -chartAndGapWidths $iconLayoutStr"
			}
			$this.width = $xOffset
		}
		if (-not $foundChart) { throw "-chartAndGapWidths element '${iconLayoutStr}' does not contain a chart width" }

		$this.chartLocations = @()
		# second loop: add each gap widths to the correct ChartLocation
		for ($i = 0; $i -lt $tmpChartLocationsAndGaps.length; $i++) {
			if ($tmpChartLocationsAndGaps[$i] -is [ChartLocation]) {
				$this.chartLocations += $tmpChartLocationsAndGaps[$i]
				continue
			}

			# search nearest chart
			$lookLeft = $true
			$lookRight = $true
			for ($dist = 1; $lookLeft -or $lookRight; $dist++) {
				# chart before current gap wins, if it has the same distance as a chart after the gap
				if ($lookLeft) {
					$lookLeft = ($i - $dist) -ge 0
					if ($lookLeft -and $tmpChartLocationsAndGaps[$i - $dist] -is [ChartLocation]) {
						$tmpChartLocationsAndGaps[$i - $dist].rightGapWidth += $tmpChartLocationsAndGaps[$i]
						break
					}
				}
				# chart after current gap
				if ($lookRight) {
					$lookRight = ($i + $dist) -lt $tmpChartLocationsAndGaps.length
					if ($lookRight -and $tmpChartLocationsAndGaps[$i + $dist] -is [ChartLocation]) {
						$tmpChartLocationsAndGaps[$i + $dist].leftGapWidth += $tmpChartLocationsAndGaps[$i]
						break
					}
				}
			}
		}
		write-debug "$iconLayoutStr -> $($this.toString())"
	}

	[uint32] $width #including gaps
	[ChartLocation[]] $chartLocations
	[string] toString() { return "IconLayout($($this.width), [$($this.chartLocations | %{$_.toString()} | join ', ')])" }
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
