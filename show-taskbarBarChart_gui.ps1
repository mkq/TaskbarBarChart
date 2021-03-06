# Copyright (c) 2021 mkq
# SPDX-License-Identifier: MIT

using namespace System.Drawing
using namespace System.Windows.Forms

# Renders a single bitmap; used when there is no value to show.
# Return type: a { bitmap = ..; text = .. } object
function defaultBitmap {
	param()
	write-debug '--- defaultBitmap ---'
	[IconLayout] $currIconLayout = $script:iconLayouts[0]
	[uint32] $currIconHeight = if ($script:iconHeight -ne 0) { $script:iconHeight } else { $currIconLayout.width }
	[Bitmap] $bitmap = newBitmap -width $currIconLayout.width -height $currIconHeight
	$fgColor, $bgColor = getColorsAt 0

	# --- draw background ---
	for ([int] $y = $bitmap.size.height - 1; $y -ge 0; $y--) {
		for ([int] $x = $bitmap.size.width - 1; $x -ge 0; $x--) {
			$bitmap.setPixel($x, $y, $bgColor)
		}
	}

	# --- draw a dash (width: half icon width, height: 4 px) ---
	for ([int] $y = $bitmap.size.height / 2 - 1; $y -le $bitmap.size.height / 2 + 2; $y++) {
		for ([uint32] $x = 0.25 * $bitmap.size.width; $x -le 0.75 * $bitmap.size.width; $x++) {
			if ($y -ge 0 -and $y -lt $bitmap.size.height) {
				$bitmap.setPixel($x, $y, $fgColor)
			}
		}
	}

	$text = "$($script:myInvocation.myCommand.name) - no values to show"
	return @{ bitmap = $bitmap; text = $text; }
}

# Renders $script:histStyledValues to as many bitmaps as needed for their count.
# Returns an array of { bitmap = ..; text = .. } objects.
# For example, given three StyledValues @( { name = 'A'; .. }, { name = 'B'; .. }, { name = 'C'; .. } )
# and $script:iconLayouts[2] (the layout to use in case of three values) has two charts,
# the result is @( { bitmap = ..; text = 'A | B' }, { bitmap = ..; text = 'C' })
function valuesToBitmaps {
	write-debug '--- valuesToBitmaps ---'
	[IconLayout] $currIconLayout = arrayElementAtOrLast -array $script:iconLayouts -index ($script:histStyledValues.length - 1) -comment '$currIconLayout'
	[uint32] $currIconHeight = if ($script:iconHeight -ne 0) { $script:iconHeight } else { $currIconLayout.width }
	write-debug "icon width: $($currIconLayout.width), height: $currIconHeight"

	$bitmapResults = @()
	$perIconChartIndex = -1 #starts at 0 for each icon; to determine when to start a new bitmap

	# --- loop: one chart per $script:histStyledValues ---
	for ($totalChartIndex = 0; $totalChartIndex -lt $script:histStyledValues.length; $totalChartIndex++) {
		[HistStyledValue] $histStyledValue = $script:histStyledValues[$totalChartIndex]
		write-debug "valuesToBitmaps: [$totalChartIndex] $($histStyledValue.toString())"
		[uint32] $maxValue = arrayElementAtOrLast -array $script:maxValues -index $totalChartIndex -comment '$maxValue'
		$fgColor, $bgColor, $unused = getColorsAt $totalChartIndex
		$tooltipText = $histStyledValue.values.first.value.tooltipText()

		if ($perIconChartIndex -lt 0 -or ($perIconChartIndex + 1) -ge $currIconLayout.chartLocations.length) {
			# start new icon
			write-debug "create new bitmap bitmapResults[$($bitmapResults.length)]"
			$bitmap = newBitmap -width $currIconLayout.width -height $currIconHeight
			$bitmapResults += , @{ bitmap = $bitmap; text = $tooltipText }
			$chartLocation = $currIconLayout.chartLocations[0]
			$perIconChartIndex = 0
		} else { # current icon has room for current value
			$chartLocation = $currIconLayout.chartLocations[++$perIconChartIndex]
			$bitmapResults[-1].text += ' | ' + $tooltipText
		}
		write-debug "chartLocation: $($chartLocation.toString())"
		write-debug "tooltip: $($bitmapResults[-1].text)"

		# draw gap left of current chart
		write-debug "draw left gap"
		drawBar -xLeft ($chartLocation.offset - $chartLocation.leftGapWidth) -width $chartLocation.leftGapWidth -relativeHeight 0 -fgColor $fgColor -bgColor $bgColor -bitmap $bitmap
		# draw gap right of current chart
		write-debug "draw right gap"
		drawBar -xLeft ($chartLocation.offset + $chartLocation.width) -width $chartLocation.rightGapWidth -relativeHeight 0 -fgColor $fgColor -bgColor $bgColor -bitmap $bitmap

		# --- loop: draw all values in history of one HistStyledValue ---
		# history order: from newest (right) to oldest (left) value
		# => if chart width is not a multiple ot barWidth, the oldest is truncated
		$x = $chartLocation.offset + $chartLocation.width
		foreach ($styledValue in $histStyledValue.values) {
			$x -= $barWidth
			$relativeHeight = ($styledValue.value / [float]$maxValue)
			write-debug "draw value at x = ${x}: $($styledValue.toString()) => relativeHeight = ${relativeHeight}"
			$valueFgColor = if ($null -ne $styledValue.color) { $styledValue.color } else { $fgColor }
			drawBar -xLeft $x -width $barWidth -relativeHeight $relativeHeight -fgColor $valueFgColor -bgColor $bgColor -bitmap $bitmap
		}
	}
	return $bitmapResults
}
 
function newBitmap {
	param([uint32] $width, [uint32] $height)
	write-debug "bitmap size: $width x $height"
	$bitmap = new-object Bitmap ([int32]$width, [int32]$height, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
	write-debug ('bitmap of size {0} created' -f $bitmap.size)
	return $bitmap
}

function drawBar {
	param(
		[Bitmap] $bitmap,
		[Color] $fgColor,
		[Color] $bgColor,
		[int] $xLeft,
		[uint32] $width,
		[float] $relativeHeight
	)
	if ($width -eq 0) {
		write-debug "drawBar: x: $xLeft, w: $width, relativeHeight: $relativeHeight => NOP"
		return
	}
	if ($xLeft -lt 0) { $width += $xLeft; $xLeft = 0 }
	$yTop = [uint32] [System.math]::round($bitmap.size.height * (1 - $relativeHeight))
	write-debug "drawBar: x: $xLeft, w: $width, relativeHeight: $relativeHeight => yTop: $yTop"
	for ([int] $xOffset = $width - 1; $xOffset -ge 0; $xOffset--) {
		$x = $xLeft + $xOffset
		for ($y = $bitmap.size.height - 1; $y -ge 0; $y--) {
			$color = if ($y -lt $yTop) { $bgColor } else { $fgColor }
			$bitmap.setPixel($x, $y, $color)
		}
	}
}

function setNotifyIconFromBitmap {
	param([NotifyIcon] $notifyIcon, [Bitmap] $bitmap)
	$oldIcon = $notifyIcon.icon
	try {
#		$bitmap256 = convertBitmapTo256Colors $bitmap; try {
		$handle = <#$bitmap256#> $bitmap.GetHicon(); try {
			$icon = [Icon]::FromHandle($handle); try {
				$notifyIcon.icon = $icon
			} finally { $icon.dispose() }
		} finally { [native.user32]::DestroyIcon($handle) | out-null }
#		} finally { $bitmap256.dispose() }
	} finally {
		if ($null -ne $oldIcon) { $oldIcon.dispose() }
	}
}

<#
# Converts a bitmap to a 256 color image [https://stackoverflow.com/a/6356108].
# 256 colors were suggested here: [https://stackoverflow.com/q/7490962].
# But using this in setNotifyIconFromBitmap did not help with bad scaling.
function convertBitmapTo256Colors {
	param([Bitmap] $bitmap)
	$stream = new-object System.IO.MemoryStream; try {
        $bitmap.save($stream, [System.Drawing.Imaging.ImageFormat]::Gif)
        $stream.position = 0
        return [Image]::fromStream($stream)
    } finally { $stream.dispose() }
}
#>

function getColorsAt {
	param([uint32] $index)
	$bgColor = arrayElementAtOrLast -array $script:bgColors -index $index -comment '$bgColor'
	$fgColor = arrayElementAtOrLast -array $script:fgColors -index $index -comment '$fgColor'
	write-debug "color: $fgColor on $bgColor"
	$bgColor = $colorConverter.convertFromString($bgColor)
	$fgColor = $colorConverter.convertFromString($fgColor)
	write-debug "converted color: $fgColor on $bgColor"
	[Color[]] @($fgColor, $bgColor)
}

# helper function to avoid WriteErrorException due to too long text
function setNotifyIconText {
	param([NotifyIcon] $notifyIcon, [string] $text)
	write-debug "setNotifyIconText: $($text.length) chars: $text"
	$notifyIcon.text = ''
	while ($text.length -gt 0) {
		try {
			$notifyIcon.text = $text
			write-debug "NotifyIcon.text with length $($text.length) succeeded"
			return
		} catch {
			write-debug "notifyIcon.text '$text' => $_"
			$text = $text.substring(0, $text.length - 2)
		}
	}
}

# Initializes $script:notifyIcons
function initNotifyIcons {
	param([uint32] $count)
	foreach ($i in 0 .. ($count - 1)) {
		write-debug "init icon $i"
		$notifyIcon = New-Object NotifyIcon
		setNotifyIconText -notifyIcon $notifyIcon -text $script:myInvocation.myCommand.name
		$notifyIcon.visible = $true
		if ($null -ne $notifyIcon.contextMenu) { $notifyIcon.contextMenu.dispose() }
		$notifyIcon.contextMenu = initContextMenu
		$notifyIcon.add_click({ $script:windowVisible = !$script:windowVisible; applyWindowVisible })
#		$notifyIcon.add_mouseMove({ param($src, $event) write-debug "MouseMove: $src, $event" })
		$script:notifyIcons += @($notifyIcon)
	}
}

function hideNotifyIcons {
	foreach ($notifyIcon in $script:notifyIcons) {
		write-debug "hide icon $notifyIcon"
		$notifyIcon.visible = $false
	}
	foreach ($notifyIcon in $script:notifyIcons) {
		write-debug "dispose icon $notifyIcon"
		try {
			$notifyIcon.contextMenu.dispose()
		} catch { write-warning "error disposing contextMenu of ${notifyIcon}: $_" }
		try {
			$notifyIcon.dispose()
		} catch { write-warning "error disposing ${notifyIcon}: $_" }
	}
	$script:notifyIcons = @()
}

function applyWindowVisible {
	param()
 	[native.user32]::ShowWindow($script:hWindow, $windowVisible) | out-null
}

function initContextMenu {
	[OutputType([ContextMenu])]
	param()
	$exitMenuItem = new-object MenuItem
	$exitMenuItem.text = "e&xit (buggy - click me plenty!)"
	# TODO: Bug: After clicking this menu item, the context menu needs to be reopened to fire the event.
	$exitMenuItem.add_click({
		write-debug 'exit menu click'
		cleanup
		stop-process $pid
	})
	$contextMenu = new-object ContextMenu
	$contextMenu.menuItems.add($exitMenuItem) | out-null
	$contextMenu
}
