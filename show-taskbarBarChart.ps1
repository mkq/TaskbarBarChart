using namespace System.Drawing
using namespace System.Windows.Forms

<#
.SYNOPSIS
Shows taskbar notification icons with bar charts.

Parameters tagged with "(valueIndexBased)" take an array of whatever type makes sense for the
parameter. The n-th element of the parameter is for the n-th value. If there are more values than
parameters, the last parameter is used.

Parameters tagged with "(valueCountBased)" take an array of whatever type makes sense for the
parameter. When n values are to be shown, the n-th (1-based) element of the parameter is used, if
given. If there are more values than parameters, the last parameter is used.
#>
[CmdletBinding()]
param (
	# Print debug messages, but turn off confirmation prompts.
	[Switch] [bool]
	$debugOutput = $false,

	# The command to execute repeatedly. It should output an array of values; each value can be
	# an unsigned int or an object with "value" property of type unsigned int and an optional
	# "name", "label", or "description" property. Default: per-core CPU usage.
	[Parameter(Mandatory=$false)] [scriptblock]
	$cmd = {
		set-strictMode -off
		if ([int] $script:cmdInvocationCount -eq 0) { write-host -noNewline 'The first invocation of Win32_PerfFormattedData_PerfOS_Processor may take a few seconds... ' }

		get-WmiObject Win32_PerfFormattedData_PerfOS_Processor | where { $_.name -ne '_total' } `
		| % { [PSCustomObject] @{ name = [int]$_.name; value = [uint32]$_.PercentProcessorTime } } `
		| sort-object -property name `
		| % { [PSCustomObject] @{ name = "CPU $($_.name)"; value = $_.value } }

		if ($script:cmdInvocationCount++ -eq 0) { write-host 'done' }
	},

	# The refresh interval in milliseconds 
	[Parameter(Mandatory=$false)] [uint32]
	$interval = 1000,

	# (valueIndexBased) For scaling: The 100% value.
	[Parameter(Mandatory=$false)] [uint32[]]
	$maxValues = @(100),

	# (valueCountBased) Icon layouts.
	# Each element is an empty string or a comma-separated list of integer negative gap widths and positive chart widths.
	# The empty string denotes System.Windows.Forms.SystemInformation.SmallIconSize.width.
	# Each gap uses the background color of the "nearest" chart in the array (not in pixels), the preceding one if ambiguous.
	# For example, given '13,-3,-2,-1,13', the middle (2 px) gap has the same array index distance from both charts, so it
	# uses the left chart's color, although its distance in pixels is 3, compared to 1 from the right chart. However, it does
	# not make sense to specify this layout this way, since it's equivalent to '13,-5,-1,13'.
	# Example chart and gap widths:
	# * '30,-4,30'    = two 30 px wide charts with 4 px gap;
	# * '-2,30,-1,-1,30' = 2 px gap, 30 px chart, 1 px gap using left chart's background color, 1 px gap using right
	# chart's background color, 30 px chart.
	# Default: @(''), i.e. a single icon layout used for any value count; consisting of a single chart; its width is
	# determined from SystemInformation.SmallIconSize.
	[Parameter(Mandatory=$false)] [string[]]
	[ValidateScript({
		function validateChartAndGapWidthsArrays {
			param([string[]] $allChartAndGapWidths)
			write-debug "validate $allChartAndGapWidths"
			if ($allChartAndGapWidths.length -lt 1) {
				write-warning '-chartAndGapWidths: at least one (array) element required.'
				return $false
			}
			foreach ($currChartAndGapWidths in $allChartAndGapWidths) {
				write-debug "validate $currChartAndGapWidths"
				# Each "icon layout" (inner array in $chartAndGapWidths) must contain at least one
				# positive number (chart width), and must not contain 0.
				$foundPositive = $false
				foreach ($w in ($currChartAndGapWidths -split '\s*,\s*')) {
					write-debug "validate chart or gap width ${w}: zero: $($w -eq 0), positive: $($w -gt 0)"
					if (-not $w -is [int]) { write-warning "-chartAndGapWidths: not as integer: $w"; return $false; }
					if ($w -eq 0) { write-warning '-chartAndGapWidths: 0 is not allowed'; return $false; }
					if ($w -gt 0) { $foundPositive = $true }
					write-debug "foundPositive in loop: $foundPositive"
				}
				write-debug "foundPositive result: $foundPositive"
				if (-not $foundPositive) {
					write-warning '-chartAndGapWidths: each layout must contain at least one positive value (i.e. chart width)'
					return $false
				}
			}
			return $true
		}
		return validateChartAndGapWidthsArrays $_
	})]
	$chartAndGapWidths = @(''),

	# Icon height in pixels. 0 = same as the width computed from the applicable $chartAndGapWidths.
	[Parameter(Mandatory=$false)] [uint32]
	$iconHeight = 0,

	# Bar width in pixels.
	# If less than the chart width (see -chartAndGapWidths), then some history is visible.
	[Parameter(Mandatory=$false)] [uint32]
	$barWidth = 1,

	# (valueIndexBased) Chart colors.
	# See method System.Drawing.ColorConverter.convertFromString for valid colors.
	[Parameter(Mandatory=$false)] [string[]]
	$fgColors = @('#ff50ff32'),
	
	# (valueIndexBased) Background colors.
	# See method System.Drawing.ColorConverter.convertFromString for valid colors.
	[Parameter(Mandatory=$false)] [string[]]
	$bgColors = @('#ff252525'),

	# Whether the console window is visible on startup. Can be toggled later by clicking an icon.
	[Parameter(Mandatory=$false)] [boolean]
	$windowVisible = $true
)

<#
TODO
- (in $cmd) group values, e.g. [9,8,7,5,3,1,1,0] -> [[9],[8],[7,5],[3,1],[1,0]], then take average
  per group, e.g. -> [9,8,6,2,1]
- Move repetition inside $cmd; in this script, refresh on each of its outputs (block while reading
  that instead of sleep).
  Or better yet, replace $cmd parameter with pipe input.
  Advantage in either case: support long-running $cmd, e.g. a "status registry HTTP service" which
  displays status colors when a client (e.g. shell coming back to prompt) posts its status.
- (in $cmd, just as a demo) color per CPU core even if sorted by load
- update tooltip (already shown) on refresh
- parameter to control scale (horizontal lines), e.g. at 25%, 50%, 75%.
  With two configurable colors? One is drawn before, one after the value bar.
#>

# --- assemblies ---
foreach ($ass in 'System.Collections', 'System.Windows.Forms', 'System.Drawing') {
	[System.Reflection.Assembly]::LoadWithPartialName($ass) | write-debug
}

# --- source other helper scripts ---
foreach ($suffix in 'util', 'gui') {
	$script = $MyInvocation.MyCommand.source -replace '\.ps1$',"_${suffix}.ps1"
	write-debug ". $script"
	. $script
}

function refresh {
	param()

	# --- invoke command; convert its output ---
	updateValues

	# --- render values to bitmaps ---
	$bitmaps = @(if ($script:histStyledValues.length -eq 0) { defaultBitmap } else { valuesToBitmaps }); try {
		write-debug "bitmaps.length: $($bitmaps.length)"

		# --- bitmaps to NotifyIcons ---
		if ($script:notifyIcons.length -ne $bitmaps.length) {
			hideNotifyIcons
			initNotifyIcons -count $bitmaps.length
		}
		<# It seems that the first drawn icon will be the left-most, but others get displayed right
		to left. E.g. to get positions a, b, c, d, e, they must be drawn in order a, e, d, c, b.
		(This applies both to making a NotifyIcon visible and changing its icon.)
		TODO: Turned out that this varies. Find a reliable way to ensure proper order.
		Maybe [https://social.msdn.microsoft.com/Forums/windowsdesktop/en-US/ec417755-1c6b-4e71-9e65-89e1c89aec88/how-to-force-order-of-icons-in-the-notification-area#e87681ba-789c-4c8f-9484-183bf7d312e0]
		#>
		$indexes = if ($bitmaps.length -le 1) { @(0) } else {
			# %{$_}: flatten e.g. (0, (4, 3, 2, 1)) to (0, 4, 3, 2, 1)
			0, (($bitmaps.length - 1) .. 1) | %{$_}
		}
		write-debug "indexes in weird NotifyIcon order: $indexes"
		foreach ($i in $indexes) {
			write-debug "bitmap [$i] to NotifyIcon"
			# TODO multi-line tooltip:
			# - header: from new script array parameter iconNames
			# - line per history entry: "<value> <name>"
			setNotifyIconText -notifyIcon $script:notifyIcons[$i] -text $bitmaps[$i].text
			setNotifyIconFromBitmap $script:notifyIcons[$i] $bitmaps[$i].bitmap
			# setting a new contextMenu every time does not fix the bug
			# $script:notifyIcons[$i].contextMenu = initContextMenu
		}
	} finally { $bitmaps | %{ $_.bitmap.dispose() } }
}

# invokes $cmd, converts its output, adds to $script:histStyledValues
function updateValues {
	write-debug '--- updateValues ---'
	write-debug 'invoke $cmd'
	$rawValues = @($cmd.invoke())
	write-debug "$($rawValues.length) rawValues: $( $rawValues | %{$_.toString()} | join ', ' )"

	# History size is determined by current number of values only.
	[IconLayout] $iconLayout = arrayElementAtOrLast -array $script:iconLayouts -index ($rawValues.length - 1) -comment '$iconLayout'
	[uint32] $maxChartWidth = ($iconLayout.chartLocations.width | measure-object -max).maximum
	[uint32] $historySize = [math]::ceiling($maxChartWidth / [double]$barWidth)
	write-debug "historySize: $historySize"

	if ($script:histStyledValues.length -ne $rawValues.length) {
		$script:histStyledValues = [HistStyledValue[]]::new($rawValues.length)
		for ($i = 0; $i -lt $rawValues.length; $i++) {
			$script:histStyledValues[$i] = new-object HistStyledValue
			$script:histStyledValues[$i].setSize($historySize)
		}
	}

	# convert each command output to a StyledValue
	$rawValues | foreach-object -begin { $i = -1 } -process {
		$i++;
		# 'name': input property name, label, or descripition; or '[<index>]'
		$n = getProperty -object $_ -property name,label,description -default ('[{0}]' -f $i)
		# 'value': already int or uint32; else input property value; else 0
		$v = $_ -as [uint32]
		$v = if ($v -ne $null) { $v } else { getProperty -object $_ -property value -default 0; } 
		# 'color': already a Color; else ColorConverter argument
		$c = getProperty -object $_ -property color,colour
		$c = if ($null -eq $c -or '' -eq $c) { $null } `
			elseif ($c -is [Color]) { $c } `
			else { $colorConverter.convertFromString($c) }
		[StyledValue] $styledValue = new-object StyledValue -property @{ name = $n; value = $v; color = $c; }
		write-debug "[$i] $($styledValue.tooltipText())"
		$script:histStyledValues[$i].add($styledValue)
	}
	write-verbose ($script:histStyledValues | % { $_.values.first.value.tooltipText() } | join ', ')
}

function cleanup {
	param()
	write-debug 'cleanup()'
	if ($null -ne $script:notifyIcons) { hideNotifyIcons }
}

# -------------------- main --------------------
set-strictMode -version 2
if (-not $PSBoundParameters['Debug'] -and $debugOutput) {
	$DebugPreference = 'Continue'
}
$startDate = get-date

$notifyIcons = @()
try {
	# ----- print parameters -----
	write-debug @"
--- parameters ---
| * cmd: $($cmd -replace "`n", "`n| ")
| * interval: $interval
| * maxValues: $maxValues
| * barWidth: $barWidth
| * chartAndGapWidths: $chartAndGapWidths
| * iconHeight: $iconHeight
| * fgColors: $fgColors
| * bgColors: $bgColors
| * windowVisible: $windowVisible
-------------------
"@

	# ----- init misc ------
	write-debug "my PID: $pid"
	$process = Get-Process -id $pid
	$smallIconSize = [System.Windows.Forms.SystemInformation]::SmallIconSize
	[IconLayout[]] $iconLayouts = $chartAndGapWidths | % {
		write-debug "convert -chartAndGapWidths element $_"
 		[IconLayout]::new($_, $smallIconSize.width)
	}
	$hWindow = $process.MainWindowHandle
	write-debug "window: $hWindow"
	write-debug "SystemInformation.SmallIconSize: $smallIconSize"
	add-type -namespace native -name user32 -member @'
			[DllImport("user32.dll")] public extern static bool ShowWindow(int handle, int state);
			[DllImport("user32.dll")] public extern static int  GetGuiResources(IntPtr hProcess, int uiFlags);
			[DllImport("user32.dll")] public extern static bool DestroyIcon(IntPtr handle);
'@
 	applyWindowVisible
#	[System.Windows.Forms.Application]::EnableVisualStyles();
	$stopWatch = new-object System.Diagnostics.StopWatch; $stopWatch.start()
	$mega = [math]::pow(2, 20)
	[HistStyledValue[]] $histStyledValues = @()
	$colorConverter = new-object ColorConverter

	write-host "`nLeft click any icon to hide or show console window."
	write-host 'Press Control+C or use any icon''s context menu to exit.'

	# ----- show default icon -----
	initNotifyIcons -count 1
	write-debug 'initial default bitmap'
	$bitmap = defaultBitmap; try {
		write-debug 'update initial default icon'
		setNotifyIconText -notifyIcon $notifyIcons[0] -text $bitmap.text
		setNotifyIconFromBitmap $notifyIcons[0] $bitmap.bitmap
	} finally { $bitmap.bitmap.dispose() }

	while (1) {
		write-debug '__________________________________________________________________________________________'

		# ----- get new values and refresh GUI -----
		refresh

		# --- print process stats ---
		$gdiHandleCount  = [native.user32]::GetGuiResources($process.handle, 0)
		$userHandleCount = [native.user32]::GetGuiResources($process.handle, 1)
		write-verbose (@(
			"this process (${pid}): running since $([int]((get-date) - $startDate).totalSeconds)s",
			"TotalProcessorTime: $([int]$process.TotalProcessorTime.TotalMilliseconds)ms",
			"WorkingSet: $([int]($process.WorkingSet/$mega))MB",
			"VirtualMemorySize: $([int]($process.VirtualMemorySize/$mega))MB",
			"handles: $($process.handleCount)", 
			"GDI handles: $gdiHandleCount",
			"user handles: $userHandleCount") -join ', ')

		# --- sleep ---
		$stopWatch.stop()
		$sleepTime = $interval - $stopWatch.elapsed.totalMilliseconds
		write-debug ('duration: {0} => sleep for {1} ms' -f $stopWatch.elapsed.totalMilliseconds, $sleepTime)
		start-sleep -millis ([System.Math]::max(0, $sleepTime))
		$stopWatch.reset(); $stopWatch.start()
	}
} catch {
	write-error $_
} finally {
	cleanup
}
