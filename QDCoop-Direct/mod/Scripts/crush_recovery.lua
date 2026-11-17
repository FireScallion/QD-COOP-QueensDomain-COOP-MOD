-- Recover only a timed-out native crushing reset, never arbitrary input locks.
return function(valid,log)
 local M={};local tracked;local since
 function M.begin(p,crushing,now)
  if not crushing or not valid(p)or not p.ActivelyResettingFromDeathPit then return end
  if tracked~=p:GetAddress()then tracked=p:GetAddress();since=now end
 end
 function M.poll(g,p,now)
  if not tracked then return end
  if not valid(p)or p:GetAddress()~=tracked or not valid(g)then tracked=nil;return end
  if not p.ActivelyResettingFromDeathPit then tracked=nil;return end
  -- Never lift another system's ownership of input. Allow a fresh grace period
  -- after a modal/teleport ends, or after a teammate revives this player.
  local d=p.DialogueManager
  if p.IsDead or p.Health<=0 or g.InCutscene or p.IsInGameplayModal or
     p.Teleporting or p.QuickTeleporting or p.DoingTeleportCrystal or p.DoingSecretTP or
     p.DoingQuickInteraction or valid(p.CurrentCutsceneManager)or
     (valid(d)and d.RunningDialogue)then since=now;return end
  if now-since<3 then return end
  local c=p:GetController();if not valid(c)then return end
  -- Match the native reset's input tail. Do not reset controller input counters,
  -- force walking, clear suspend-save blockers, heal, or teleport a second time.
  p:EnableInput(c)
  p.ActivelyResettingFromDeathPit=false
  p:SetTeleportedRecently()
  tracked=nil
  log('CRUSH RECOVERY cleared stalled native reset after 3s; player='..p:GetFullName())
 end
 return M
end
