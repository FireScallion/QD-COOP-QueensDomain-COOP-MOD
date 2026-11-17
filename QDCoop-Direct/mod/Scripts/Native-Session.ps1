param([Parameter(Mandatory=$true)][int]$OwnerPid,[Parameter(Mandatory=$true)][long]$OwnerFileTime,[Parameter(Mandatory=$true)][string]$SaveDirectory)
$ErrorActionPreference='Stop'
# A PowerShell 7 parent may supply a PSModulePath without Windows PowerShell's
# built-in script modules. Bootstrap always launches Windows PowerShell 5.1.
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1')
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../../../../'))
$mod=Join-Path $root 'QDCoop-Direct'
$state=Join-Path $mod 'Local/native'
$ipc=Join-Path $state 'ipc'
$run="${OwnerPid}_${OwnerFileTime}"
$diagnosticRun=$null
$collectDiagnostics=$false
function DiagnosticEvent($text){
 if(!$diagnosticRun){return}
 try{[IO.File]::AppendAllText((Join-Path $diagnosticRun 'capture-status.txt'),([DateTime]::UtcNow.ToString('o')+' '+$text+"`n"))}catch{}
}
function WriteUtf8($p,$s){[IO.File]::WriteAllText($p,$s,[Text.UTF8Encoding]::new($false))}
function LuaString($s){if($s.Contains(']===]')){throw 'Unsupported path'};return '[===['+$s.Replace('\','/')+']===]'}
$owner=$null;$bridge=$null;$steam=$null;$lock=$null;$nextSteamStart=[DateTime]::MinValue
function EnsureSteamService {
 if($script:steam -and !$script:steam.HasExited){return $true}
 if(!$steamDll){return $false}
 if($script:steam){$script:steam.Dispose();$script:steam=$null}
 try{
  Remove-Item -LiteralPath (Join-Path $ipc 'stop.steam') -ErrorAction SilentlyContinue
  $script:steam=Start-Process -FilePath (Join-Path $mod 'standalone/QDCoopBridge.exe') -ArgumentList ('--steam-service "'+$steamCfg+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'steam-stdout.txt') -RedirectStandardError (Join-Path $state 'steam-stderr.txt')
  WriteUtf8 (Join-Path $state 'steam.pid') ([string]$script:steam.Id)
  WriteUtf8 (Join-Path $ipc 'steam-ui.txt') 'starting|0|'
  return $true
 }catch{WriteUtf8 (Join-Path $ipc 'steam-ui.txt') 'unavailable|0|Steam service could not start';return $false}
 finally{$script:nextSteamStart=[DateTime]::UtcNow.AddSeconds(30)}
}
function SteamCommand($role,$token,$port=0,$lobby=''){
 $roomCapacity=2;$roomProtocol=1
 if($cfg -and $cfg.ContainsKey('MaxPlayers')){$roomCapacity=$cfg.MaxPlayers;$roomProtocol=$cfg.RoomProtocol}
 $p=Join-Path $ipc 'steam.command';$json=@{Role=$role;Token=$token;Port=$port;Lobby=$lobby;MaxPlayers=$roomCapacity;RoomProtocol=$roomProtocol}|ConvertTo-Json
 # Readers can briefly hold the previous control file without delete sharing.
 # Retry only in this background supervisor; never stall or tear down LAN.
 for($attempt=0;$attempt -lt 5;$attempt++){
  try{WriteUtf8 ($p+'.tmp') $json;Move-Item -LiteralPath ($p+'.tmp') -Destination $p -Force;return}catch{if($attempt -lt 4){Start-Sleep -Milliseconds 20}}
 }
}
try {
 $owner=Get-Process -Id $OwnerPid
 if($owner.StartTime.ToUniversalTime().ToFileTimeUtc() -ne $OwnerFileTime){throw 'Game process identity mismatch'}
 $heldHandle=$owner.Handle
 [IO.Directory]::CreateDirectory($ipc) | Out-Null
 $lock=[IO.File]::Open((Join-Path $state 'session.lock'),'OpenOrCreate','ReadWrite','None')
 if($collectDiagnostics){try{
  $captureRoot=Join-Path $mod 'Local/NetworkDiagnostics'
  $path=Join-Path $captureRoot ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+$run)
  [IO.Directory]::CreateDirectory($path) | Out-Null
  $diagnosticRun=$path
  DiagnosticEvent 'schema=2 stage=game_start build=1.2.4'
  [IO.File]::WriteAllText((Join-Path $path 'steam-network-history.txt'),"schema=2 waiting_for_steam_service`n")
 }catch{}}
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
 $sessionToken=[Guid]::NewGuid().ToString('N')
 $channel='Local\QDCoopIPC2_'+$sessionToken
 # Load only the Valve-signed Steam API belonging to this game installation.
 # An unavailable Steam service never prevents the existing LAN mode starting.
 $steamDll=$null
 try{
  $candidates=@(Get-ChildItem -LiteralPath (Join-Path $root 'Engine/Binaries/ThirdParty/Steamworks') -Filter steam_api64.dll -File -Recurse)
  foreach($candidate in $candidates){$signature=Get-AuthenticodeSignature -LiteralPath $candidate.FullName;if($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match 'O=Valve Corp\.'){$steamDll=$candidate.FullName;break}}
 }catch{}
 $config='return {NativeStartup=true,RoomProtocol=2,MaxPlayers=4,RunOwner="'+$run+'",RunId="'+$sessionToken+'",Role="menu",MenuMode=true,AutoLoadSlot=false,TargetHP=400,Ipc='+(LuaString $ipc)+',IpcChannel='+('[['+$channel+']]')+',ExpectedSaveDirectory='+(LuaString $savePath)+',GenerationalGC=true,InlineWeakValidation=true,NativeObjectReferences=true,NativeEffectValidation=true,NativeKnownEnemyDiscovery=true,NativeSpear=true,OffscreenEnemyAnimation=true,NativeFarAnimation=true,NativePresentation=true,NativeBodyRead=true,ReuseBodyPose=true,NativeEnemyCapture=true,NativeEnemyPlacement=true,MotionTrace=false}'
 $config=$config.Replace('NativeStartup=true,',('NativeStartup=true,PerformanceDiagnostics='+$collectDiagnostics.ToString().ToLowerInvariant()+',SteamOverlay='+$(if($steamDll){'true'}else{'false'})+','))
 if($steamDll){$config=$config.Replace('NativeStartup=true,',('NativeStartup=true,SteamLibrary='+(LuaString $steamDll)+','))}
 WriteUtf8 (Join-Path $state 'config.lua') $config
 $cfg=@{Role='host';Host='127.0.0.1';Port=47771;Key='QDCoop-LAN-test-2026';Directory=$ipc;OwnerPid=$OwnerPid;OwnerStartTicks=$owner.StartTime.ToUniversalTime().Ticks;Build='qdcoop-1.2.7';IpcChannel=$channel}
 if($steamDll){try{
  $steamCfg=Join-Path $state 'steam.json'
  WriteUtf8 $steamCfg (@{Directory=$ipc;Dll=$steamDll;Build=$cfg.Build;OwnerPid=$OwnerPid;OwnerStartTicks=$cfg.OwnerStartTicks;DiagnosticDirectory=$diagnosticRun}|ConvertTo-Json)
  $null=EnsureSteamService
 }catch{WriteUtf8 (Join-Path $ipc 'steam-ui.txt') 'unavailable|0|Steam service could not start'}}else{WriteUtf8 (Join-Path $ipc 'steam-ui.txt') 'unavailable|0|Official Steam installation required; LAN remains available'}
 $cfgPath=Join-Path $state 'bridge.json'
 $lastRequest=''
 $roomNumber=0
 DiagnosticEvent "stage=game_ready build=$($cfg.Build) steamSdkFound=$([bool]$steamDll)"
 while(!$owner.HasExited){
  $request='';try{if(Test-Path -LiteralPath (Join-Path $ipc 'session.request')){$request=[IO.File]::ReadAllText((Join-Path $ipc 'session.request'))}}catch [IO.IOException]{$request=$lastRequest}
  if($request -ne $lastRequest){
   if($lastRequest){DiagnosticEvent "stage=room_end room=$roomNumber"}
   if($bridge -and !$bridge.HasExited){WriteUtf8 (Join-Path $ipc 'stop.bridge') '';if(!$bridge.WaitForExit(2000)){$bridge.Kill();$bridge.WaitForExit()}}
   if($bridge){$bridge.Dispose();$bridge=$null}
   $lastRequest=$request
   SteamCommand 'idle' ([Guid]::NewGuid().ToString('N'))
   foreach($f in @('session.error','session.ready','in.state','status.txt')){WriteUtf8 (Join-Path $ipc $f) ''}
   if($request){try{
    $roomNumber++
    $parts=$request.Split('|');if($parts.Count -notin @(5,7) -or $parts[0] -notin @('host','host-steam','host-lan','client','steam')){throw 'Invalid room request'}
    $cfg['DiagnosticDirectory']=$null
    DiagnosticEvent "stage=room_request room=$roomNumber mode=$($parts[0]) token=$($parts[4])"
    if($diagnosticRun){
     try{
      $captureRoom=Join-Path $diagnosticRun ('room-{0:D3}-{1}' -f $roomNumber,$parts[0])
      [IO.Directory]::CreateDirectory($captureRoom) | Out-Null
      $cfg['DiagnosticDirectory']=$captureRoom
      [IO.File]::WriteAllText((Join-Path $captureRoom 'combat-transport-trace.txt'),"schema=2 waiting_for_combat_events`n")
     }catch{DiagnosticEvent "stage=room_capture_error room=$roomNumber"}
    }
    $seats=2;$protocol=1
    if($parts.Count -eq 7){$seats=[int]$parts[5];$protocol=[int]$parts[6];if($seats -lt 2 -or $seats -gt 4 -or $protocol -notin @(1,2) -or ($protocol -eq 1 -and $seats -ne 2)){throw 'Invalid room capacity or protocol'}}
    $cfg['MaxPlayers']=$seats;$cfg['RoomProtocol']=$protocol;$cfg['RoomToken']=$parts[4]
    if($parts[0] -in @('host','host-steam','steam')){$null=EnsureSteamService}
    if($parts[0] -eq 'host-steam' -and (!$steam -or $steam.HasExited)){throw 'Steam is unavailable; choose Host LAN game to play over LAN'}
    if($parts[0] -eq 'steam'){
     if(!$steam -or $steam.HasExited -or $parts[1] -notmatch '^\d{1,20}$'){throw 'Steam is unavailable'}
     SteamCommand 'join' $parts[4] 0 $parts[1]
     $deadline=[DateTime]::UtcNow.AddSeconds(35);$steamReady=$null
     while(!$owner.HasExited -and !$steam.HasExited -and [DateTime]::UtcNow -lt $deadline){
      if([IO.File]::ReadAllText((Join-Path $ipc 'session.request')) -ne $request){break}
      try{$ss=Get-Content -LiteralPath (Join-Path $ipc 'steam.status') -Raw|ConvertFrom-Json}catch{$ss=$null}
      if($ss -and $ss.Token -eq $parts[4]){if($ss.State -eq 'joined'){$steamReady=$ss;break};if($ss.State -eq 'error'){throw $ss.Error}}
      $null=$owner.WaitForExit(100)
     }
     if(!$steamReady){throw 'Steam connection was cancelled or timed out'}
     $cfg.Role='client';$cfg.Host='127.0.0.1';$cfg.Port=[int]$steamReady.Port
    }else{
     $address=[Net.IPAddress]::Parse($parts[1]);$port=[int]$parts[2]
     if($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or $port -lt 1024 -or $port -gt 65535){throw 'Invalid IP or port'}
     $cfg.Role=if($parts[0].StartsWith('host')){'host'}else{$parts[0]};$cfg.Host=$parts[1];$cfg.Port=$port
    }
    WriteUtf8 $cfgPath ($cfg|ConvertTo-Json)
    if($diagnosticRun){Remove-Item -LiteralPath (Join-Path $ipc 'attack-feedback-status.txt') -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath (Join-Path $ipc 'stop.bridge') -ErrorAction SilentlyContinue
    $bridge=Start-Process -FilePath (Join-Path $mod 'standalone/QDCoopBridge.exe') -ArgumentList ('"'+$cfgPath+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'bridge-stdout.txt') -RedirectStandardError (Join-Path $state 'bridge-stderr.txt')
    WriteUtf8 (Join-Path $state 'bridge.pid') ([string]$bridge.Id)
    WriteUtf8 (Join-Path $ipc 'session.ready') $request
    if($parts[0] -in @('host','host-steam') -and $steam -and !$steam.HasExited){SteamCommand 'host' $parts[4] $port}
   }catch{DiagnosticEvent "stage=room_error room=$roomNumber error=$($_.Exception.Message)";WriteUtf8 (Join-Path $ipc 'session.error') $_.Exception.Message}}
  }
  if($bridge -and $bridge.HasExited){DiagnosticEvent "stage=bridge_exit room=$roomNumber exit=$($bridge.ExitCode)";WriteUtf8 (Join-Path $ipc 'session.error') 'Connection service exited. Return to Multiplayer and try again.';SteamCommand 'idle' ([Guid]::NewGuid().ToString('N'));$bridge.Dispose();$bridge=$null}
  if($steam -and $steam.HasExited){DiagnosticEvent "stage=steam_service_exit exit=$($steam.ExitCode)";WriteUtf8 (Join-Path $ipc 'steam-ui.txt') 'unavailable|0|Steam service unavailable; LAN remains available';$steam.Dispose();$steam=$null}
  # A failed Steam helper used to stay unavailable until the entire game was
  # restarted. Recover the host adapter independently of its working LAN room.
  # Guest transport ports cannot be changed under a live session; guests retry
  # through the menu, which also restarts the helper above.
  if(!$steam -and $steamDll -and [DateTime]::UtcNow -ge $nextSteamStart -and (!$bridge -or $cfg.Role -eq 'host')){
   if(EnsureSteamService){if($bridge -and !$bridge.HasExited -and ($lastRequest.StartsWith('host|') -or $lastRequest.StartsWith('host-steam|'))){SteamCommand 'host' $cfg.RoomToken $cfg.Port}}
  }
  $null=$owner.WaitForExit(500)
 }
} catch {
 DiagnosticEvent "stage=bootstrap_error error=$($_.Exception.Message)"
 if($lock){WriteUtf8 (Join-Path $state 'bootstrap.log') $_.Exception.ToString()}
} finally {
 if($lock){
  try{WriteUtf8 (Join-Path $ipc 'stop.bridge') '';if($bridge -and !$bridge.HasExited){if(!$bridge.WaitForExit(2000)){$bridge.Kill()}}}catch{}
  try{WriteUtf8 (Join-Path $ipc 'stop.steam') '';if($steam -and !$steam.HasExited){if(!$steam.WaitForExit(2000)){$steam.Kill()}}}catch{}
  DiagnosticEvent 'stage=game_end'
  $lock.Dispose()
 }
 if($steam){$steam.Dispose()};if($bridge){$bridge.Dispose()};if($owner){$owner.Dispose()}
}
