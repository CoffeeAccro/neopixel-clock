<#
.SYNOPSIS
    Build and flash the NeoPixel clock firmware and/or LittleFS filesystem to an
    ESP8266, using the standalone esptool (v5+) which is more reliable than the
    esptool bundled with the old espressif8266 PlatformIO platform.

.DESCRIPTION
    Handles the quirks of this particular board:
      - Uses esptool v5 (`py -m esptool`) instead of PlatformIO's built-in uploader.
      - Uses `dout` flash mode / 40MHz / 4MB, matching platformio.ini and the
        eagle.flash.4m1m layout (firmware @ 0x0, filesystem @ 0x300000).
      - Supports a "manual" mode for boards whose auto-reset is unreliable:
        you put the chip into the ROM bootloader by hand, then it flashes without
        toggling reset.

.PARAMETER Target
    What to flash: fw | fs | both  (default: both)

.PARAMETER Port
    Serial port (e.g. COM12). If omitted, the first FTDI/USB serial port is used.

.PARAMETER Baud
    Upload baud rate (default: 115200).

.PARAMETER Manual
    Do NOT let esptool toggle reset. Requires you to manually enter the ROM
    bootloader first (hold Program -> tap Reset -> release Program). Use this if
    automatic reset doesn't work on your board.

.PARAMETER NoBuild
    Skip the (re)build step and flash whatever is already in .pio\build.

.EXAMPLE
    # Auto-reset, build + flash everything:
    .\flash.ps1

.EXAMPLE
    # Manual bootloader entry, flash only the firmware on COM12:
    .\flash.ps1 -Target fw -Port COM12 -Manual
#>

[CmdletBinding()]
param(
    [ValidateSet('fw', 'fs', 'both')]
    [string]$Target = 'both',
    [string]$Port,
    [int]$Baud = 115200,
    [switch]$Manual,
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$projectDir = $PSScriptRoot
Set-Location $projectDir

#  Flash layout for board esp12e (eagle.flash.4m1m.ld)
$FW_OFFSET  = '0x0'
$FS_OFFSET  = '0x300000'
$FW_BIN     = Join-Path $projectDir '.pio\build\esp12e\firmware.bin'
$FS_BIN     = Join-Path $projectDir '.pio\build\esp12e\littlefs.bin'
$FLASH_ARGS = @('--flash-mode', 'dout', '--flash-freq', '40m', '--flash-size', '4MB')

function Resolve-Port {
    if ($Port) { return $Port }
    $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    if ($ports.Count -eq 0) {
        throw "No serial ports found. Plug in the board (check the USB-to-UART driver) and retry, or pass -Port."
    }
    if ($ports.Count -gt 1) {
        throw "Multiple serial ports found ($($ports -join ', ')). Specify one with -Port."
    }
    Write-Host "Auto-detected serial port: $($ports[0])" -ForegroundColor Cyan
    return $ports[0]
}

function Ensure-Esptool {
    try { py -m esptool version *> $null } catch {
        Write-Host "Installing esptool..." -ForegroundColor Yellow
        py -m pip install -q esptool
    }
}

function Invoke-Flash([string]$offset, [string]$bin, [string]$label) {
    if (-not (Test-Path $bin)) { throw "$label image not found: $bin (run without -NoBuild first)." }

    if ($Manual) {
        Write-Host ""
        Write-Host ">>> Put the board in bootloader mode now:" -ForegroundColor Yellow
        Write-Host "    hold Program (SW3) -> tap Reset (SW1) -> release Program" -ForegroundColor Yellow
        Read-Host "    Press Enter when ready to flash $label"
        $before = 'no-reset'
    }
    else {
        $before = 'default-reset'
    }

    Write-Host "Flashing $label ($bin) to $offset on $resolvedPort @ $Baud..." -ForegroundColor Cyan
    py -m esptool --chip esp8266 --port $resolvedPort --baud $Baud `
        --before $before --after hard-reset --connect-attempts 5 `
        write-flash @FLASH_ARGS $offset $bin
    if ($LASTEXITCODE -ne 0) { throw "$label flash failed (exit $LASTEXITCODE)." }
    Write-Host "$label flashed OK." -ForegroundColor Green
}

Ensure-Esptool
$resolvedPort = Resolve-Port

if (-not $NoBuild) {
    if ($Target -eq 'fw' -or $Target -eq 'both') {
        Write-Host "Building firmware..." -ForegroundColor Cyan
        py -m platformio run
        if ($LASTEXITCODE -ne 0) { throw "Firmware build failed." }
    }
    if ($Target -eq 'fs' -or $Target -eq 'both') {
        Write-Host "Building filesystem image..." -ForegroundColor Cyan
        py -m platformio run -t buildfs
        if ($LASTEXITCODE -ne 0) { throw "Filesystem build failed." }
    }
}

if ($Target -eq 'fw' -or $Target -eq 'both') { Invoke-Flash $FW_OFFSET $FW_BIN 'firmware' }
if ($Target -eq 'fs' -or $Target -eq 'both') { Invoke-Flash $FS_OFFSET $FS_BIN 'filesystem' }

Write-Host ""
Write-Host "All done. The board will hard-reset into the app." -ForegroundColor Green
