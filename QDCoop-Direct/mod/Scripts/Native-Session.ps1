param([Parameter(Mandatory=$true)][int]$OwnerPid,[Parameter(Mandatory=$true)][long]$OwnerFileTime,[Parameter(Mandatory=$true)][string]$SaveDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../../../../'))
$mod=Join-Path $root 'QDCoop-Direct'
$state=Join-Path $mod 'Local/native'
$ipc=Join-Path $state 'ipc'
$run="${OwnerPid}_${OwnerFileTime}"
function WriteUtf8($p,$s){[IO.File]::WriteAllText($p,$s,[Text.UTF8Encoding]::new($false))}
function LuaString($s){if($s.Contains(']===]')){throw 'Unsupported path'};return '[===['+$s.Replace('\','/')+']===]'}
$owner=$null;$bridge=$null;$lock=$null
try {
 $owner=Get-Process -Id $OwnerPid
 if($owner.StartTime.ToUniversalTime().ToFileTimeUtc() -ne $OwnerFileTime){throw 'Game process identity mismatch'}
 $heldHandle=$owner.Handle
 [IO.Directory]::CreateDirectory($ipc) | Out-Null
 $lock=[IO.File]::Open((Join-Path $state 'session.lock'),'OpenOrCreate','ReadWrite','None')
 WriteUtf8 (Join-Path $state 'bootstrap.log') ('Starting '+$run+"`n")
 WriteUtf8 (Join-Path $state 'game.pid') ([string]$OwnerPid)
 # Backup real saves before exposing Multiplayer; never import old isolated saves.
 $savePath=[IO.Path]::GetFullPath($SaveDirectory)
 $saveGames=Join-Path $savePath 'SaveGames'
 if(Test-Path -LiteralPath $saveGames){
  $backup=Join-Path $mod ('Backups/'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
  [IO.Directory]::CreateDirectory($backup) | Out-Null
  Copy-Item -LiteralPath $saveGames -Destination $backup -Recurse
 }
 # Only volatile mailboxes are cleared. Persistent rescue/character data is in SaveGames.
 foreach($f in Get-ChildItem -LiteralPath $ipc -File){Remove-Item -LiteralPath $f.FullName}
 # The compatibility key includes original game archives, cached by file stamps.
 $archives=@(Get-ChildItem -LiteralPath (Join-Path $root 'QueensDomain/Content/Paks') -File -Recurse|Where-Object {$_.Extension -in @('.pak','.utoc','.ucas') -and $_.Name -notlike 'QDCoop-*'}|Sort-Object FullName)
 if(!$archives.Count){throw 'Original game archives missing'}
 $stamp=($archives|ForEach-Object {$_.FullName.Substring($root.Length)+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks}) -join "`n"
 $cachePath=Join-Path $state 'archive-identity.json'
 $cache=$null;try{if(Test-Path -LiteralPath $cachePath){$cache=Get-Content -LiteralPath $cachePath -Raw|ConvertFrom-Json}}catch{}
 if(!$cache -or $cache.Stamp -ne $stamp){
  $hashes=($archives|ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash }) -join '|'
  $sha=[Security.Cryptography.SHA256]::Create();try{$fingerprint=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($hashes))).Replace('-','').Substring(0,24)}finally{$sha.Dispose()}
  $cache=@{Stamp=$stamp;Fingerprint=$fingerprint};WriteUtf8 $cachePath ($cache|ConvertTo-Json)
 }
 $sessionToken=[Guid]::NewGuid().ToString('N')
 $channel='Local\QDCoopIPC2_'+$sessionToken
 $config='return {NativeStartup=true,RunOwner="'+$run+'",RunId="'+$sessionToken+'",Role="menu",MenuMode=true,AutoLoadSlot=false,TargetHP=400,Ipc='+(LuaString $ipc)+',IpcChannel='+('[['+$channel+']]')+',ExpectedSaveDirectory='+(LuaString $savePath)+',GenerationalGC=true,InlineWeakValidation=true,NativeObjectReferences=true,NativeEffectValidation=true,NativeKnownEnemyDiscovery=true,NativeSpear=true,OffscreenEnemyAnimation=true,NativeFarAnimation=true,NativePresentation=true,NativeBodyRead=true,ReuseBodyPose=true,NativeEnemyCapture=true,NativeEnemyPlacement=true,MotionTrace=false}'
 WriteUtf8 (Join-Path $state 'config.lua') $config
 $cfg=@{Role='host';Host='127.0.0.1';Port=47771;Key='QDCoop-LAN-test-2026';Directory=$ipc;OwnerPid=$OwnerPid;OwnerStartTicks=$owner.StartTime.ToUniversalTime().Ticks;Build=('qdcoop-1.17.3-'+$cache.Fingerprint);IpcChannel=$channel}
 $cfgPath=Join-Path $state 'bridge.json'
 $lastRequest=''
 while(!$owner.HasExited){
  $request='';try{if(Test-Path -LiteralPath (Join-Path $ipc 'session.request')){$request=[IO.File]::ReadAllText((Join-Path $ipc 'session.request'))}}catch [IO.IOException]{$request=$lastRequest}
  if($request -ne $lastRequest){
   if($bridge -and !$bridge.HasExited){WriteUtf8 (Join-Path $ipc 'stop.bridge') '';if(!$bridge.WaitForExit(2000)){$bridge.Kill();$bridge.WaitForExit()}}
   if($bridge){$bridge.Dispose();$bridge=$null}
   $lastRequest=$request
   foreach($f in @('session.error','session.ready','in.state','status.txt')){WriteUtf8 (Join-Path $ipc $f) ''}
   if($request){try{
    $parts=$request.Split('|');if($parts.Count -ne 5 -or $parts[0] -notin @('host','client')){throw 'Invalid room request'}
    $address=[Net.IPAddress]::Parse($parts[1]);$port=[int]$parts[2]
    if($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $port -lt 1024 -or $port -gt 65535){throw 'Invalid IP or port'}
    $cfg.Role=$parts[0];$cfg.Host=$parts[1];$cfg.Port=$port
    WriteUtf8 $cfgPath ($cfg|ConvertTo-Json)
    Remove-Item -LiteralPath (Join-Path $ipc 'stop.bridge') -ErrorAction SilentlyContinue
    $bridge=Start-Process -FilePath (Join-Path $mod 'standalone/QDCoopBridge.exe') -ArgumentList ('"'+$cfgPath+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'bridge-stdout.txt') -RedirectStandardError (Join-Path $state 'bridge-stderr.txt')
    WriteUtf8 (Join-Path $state 'bridge.pid') ([string]$bridge.Id)
    WriteUtf8 (Join-Path $ipc 'session.ready') $request
   }catch{WriteUtf8 (Join-Path $ipc 'session.error') $_.Exception.Message}}
  }
  if($bridge -and $bridge.HasExited){WriteUtf8 (Join-Path $ipc 'session.error') 'Connection service exited. Return to Multiplayer and try again.';$bridge.Dispose();$bridge=$null}
  $null=$owner.WaitForExit(500)
 }
} catch {
 if($lock){WriteUtf8 (Join-Path $state 'bootstrap.log') $_.Exception.ToString()}
} finally {
 if($lock){
  try{WriteUtf8 (Join-Path $ipc 'stop.bridge') '';if($bridge -and !$bridge.HasExited){if(!$bridge.WaitForExit(2000)){$bridge.Kill()}}}catch{}
  $lock.Dispose()
 }
 if($bridge){$bridge.Dispose()};if($owner){$owner.Dispose()}
}
