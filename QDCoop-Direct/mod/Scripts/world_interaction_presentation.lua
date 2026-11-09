-- Recreate only presentation after the native save restore. Never call Interact/Open reward paths.
return function(valid,gs)
 local M={};local time=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 function M.before(a)
  if a:IsA('/Game/Blueprints/Door_Base.Door_Base_C')then
   local timelines={};for _,v in ipairs(a:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.TimelineComponent')))do local t=v:get();if valid(t)then timelines[#timelines+1]={t=t,position=t:GetPlaybackPosition()}end end
   return {kind='door',opened=a.Opened,timelines=timelines}
  elseif a:IsA('/Game/Blueprints/SecretWall.SecretWall_C')then return {kind='secret',opened=a.Opened,running=a.AnimRunning}
  elseif a:IsA('/Game/Props/Chest_00/Chest.Chest_C')then return {kind='chest',opened=a.InteractBox:GetCollisionEnabled()==0,running=a.OpenLid:IsPlaying()}end
 end
 function M.after(a,b)
  if not b then return end
  if b.kind=='door'then if a.Opened~=b.opened then
   -- RestoreFromSave seeks the original timeline to its endpoint. Rewind only
   -- its presentation before letting the native Open/Close event resume it.
   for _,v in ipairs(b.timelines)do if valid(v.t)then v.t:SetPlaybackPosition(v.position,false,true)end end
   if a.Opened then a:OpenDoor()else a:CloseDoor()end
  end
  elseif b.kind=='chest'then
   if not b.opened and not b.running and a.InteractBox:GetCollisionEnabled()==0 then
    a.OpenLid:PlayFromStart()
    if valid(a.OpenSound)then gs:PlaySoundAtLocation(a,a.OpenSound,a:K2_GetActorLocation(),{Pitch=0,Yaw=0,Roll=0},1,1,0,nil,nil,nil)end
   end
  elseif b.kind=='secret'and a.Opened~=b.opened and not b.running then
   a.AnimStartTime=time:GetGameTimeInSeconds(a);a.AnimRunning=true;a:SetActorTickEnabled(true)
   local sound=valid(a.OpenSoundOverride)and a.OpenSoundOverride or a.OpenSound
   if valid(sound)then
    a.OpeningSoundComp=gs:SpawnSoundAttached(sound,a.DefaultSceneRoot,FName('None'),{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},0,false,1,1,0,nil,nil,true)
    if valid(a.OpeningSoundComp)then a.OpeningSoundComp:FadeIn(.2,1,0,0)end
   end
  end
 end
 return M
end
