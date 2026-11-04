param([Parameter(Mandatory = $true)][string]$Path)

$ErrorActionPreference = 'Stop'
$resolvedPath = [IO.Path]::GetFullPath($Path)
$script:PeData = [IO.File]::ReadAllBytes($resolvedPath)
$script:ChangedPaddingBytes = 0

function Read-U16([int]$Offset) { [BitConverter]::ToUInt16($script:PeData, $Offset) }
function Read-U32([int]$Offset) { [BitConverter]::ToUInt32($script:PeData, $Offset) }
function Align-Four([int]$Offset) { ($Offset + 3) -band -4 }

if ($script:PeData.Length -lt 64 -or (Read-U16 0) -ne 0x5A4D) { throw 'Invalid DOS header.' }
$peOffset = [int](Read-U32 0x3C)
if ((Read-U32 $peOffset) -ne 0x4550) { throw 'Invalid PE header.' }
$sectionCount = Read-U16 ($peOffset + 6)
$optionalOffset = $peOffset + 24
$optionalSize = Read-U16 ($peOffset + 20)
$magic = Read-U16 $optionalOffset
if ($magic -eq 0x20B) { $directoryOffset = $optionalOffset + 112 }
elseif ($magic -eq 0x10B) { $directoryOffset = $optionalOffset + 96 }
else { throw 'Unsupported PE format.' }
if ((Read-U32 ($directoryOffset + 32)) -ne 0) { throw 'Refusing to modify a signed executable.' }
$script:SectionHeaders = $optionalOffset + $optionalSize
$script:SectionCount = $sectionCount

function Convert-Rva([uint32]$Rva) {
    for ($index = 0; $index -lt $script:SectionCount; $index++) {
        $section = $script:SectionHeaders + 40 * $index
        $address = Read-U32 ($section + 12)
        $size = [Math]::Max((Read-U32 ($section + 8)), (Read-U32 ($section + 16)))
        if ($Rva -ge $address -and $Rva -lt ($address + $size)) {
            return [int]((Read-U32 ($section + 20)) + $Rva - $address)
        }
    }
    throw 'Resource RVA is outside the PE sections.'
}

$script:ResourceBase = Convert-Rva (Read-U32 ($directoryOffset + 16))

function Get-ResourceEntries([int]$Offset) {
    $count = (Read-U16 ($Offset + 12)) + (Read-U16 ($Offset + 14))
    for ($index = 0; $index -lt $count; $index++) {
        $entry = $Offset + 16 + 8 * $index
        $name = Read-U32 $entry
        $target = Read-U32 ($entry + 4)
        [pscustomobject]@{
            Id = ($name -band 0x7FFFFFFF)
            Named = ($name -gt 0x7FFFFFFF)
            Directory = ($target -gt 0x7FFFFFFF)
            Target = $script:ResourceBase + [int]($target -band 0x7FFFFFFF)
        }
    }
}

function Get-ResourceLeaves([int]$Offset, [int]$Depth = 0) {
    if ($Depth -gt 3) { throw 'Invalid resource directory depth.' }
    foreach ($entry in (Get-ResourceEntries $Offset)) {
        if ($entry.Directory) { Get-ResourceLeaves $entry.Target ($Depth + 1) }
        else { $entry.Target }
    }
}

function Clear-Padding([int]$Start, [int]$End) {
    for ($index = $Start; $index -lt $End; $index++) {
        if ($script:PeData[$index] -ne 0) {
            $script:PeData[$index] = 0
            $script:ChangedPaddingBytes++
        }
    }
}

function Normalize-VersionBlock([int]$Start, [int]$Limit) {
    $length = Read-U16 $Start
    $valueLength = Read-U16 ($Start + 2)
    $type = Read-U16 ($Start + 4)
    $end = $Start + $length
    if ($length -lt 6 -or $end -gt $Limit) { throw 'Invalid version-information block.' }
    $keyEnd = $Start + 6
    while ($keyEnd + 2 -le $end -and (Read-U16 $keyEnd) -ne 0) { $keyEnd += 2 }
    $keyEnd += 2
    if ($keyEnd -gt $end) { throw 'Unterminated version-information key.' }
    $valueStart = Align-Four $keyEnd
    Clear-Padding $keyEnd ([Math]::Min($valueStart, $end))
    $valueBytes = if ($type -eq 1) { $valueLength * 2 } else { $valueLength }
    $valueEnd = $valueStart + $valueBytes
    if ($valueEnd -gt $end) { throw 'Invalid version-information value.' }
    $child = Align-Four $valueEnd
    Clear-Padding $valueEnd ([Math]::Min($child, $end))
    while ($child + 6 -le $end) {
        $childLength = Read-U16 $child
        if ($childLength -eq 0) { break }
        Normalize-VersionBlock $child $end
        $next = Align-Four ($child + $childLength)
        Clear-Padding ($child + $childLength) ([Math]::Min($next, $end))
        $child = $next
    }
}

$versionCount = 0
foreach ($entry in (Get-ResourceEntries $script:ResourceBase)) {
    if ($entry.Named -or $entry.Id -ne 16 -or !$entry.Directory) { continue }
    foreach ($leaf in (Get-ResourceLeaves $entry.Target)) {
        $offset = Convert-Rva (Read-U32 $leaf)
        $size = Read-U32 ($leaf + 4)
        if ($offset + $size -gt $script:PeData.Length) { throw 'Version resource exceeds file size.' }
        Normalize-VersionBlock $offset ($offset + $size)
        $versionCount++
    }
}
if ($versionCount -eq 0) { throw 'No version-information resource found.' }
if ($script:ChangedPaddingBytes -gt 0) { [IO.File]::WriteAllBytes($resolvedPath, $script:PeData) }
Write-Output ("Normalized {0} padding bytes in {1} version resource(s)." -f $script:ChangedPaddingBytes, $versionCount)
