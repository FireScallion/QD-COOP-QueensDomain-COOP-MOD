-- Resolve the reflected API once per session. Do not identify game compatibility
-- from an executable hash or retry a mutating call with different arguments.
return function()
 local M={};local slotArity,pauseArity
 local function parameters(path,expected)
  local f=StaticFindObject(path)
  assert(f and f:IsValid(),'Native function unavailable: '..path)
  local names={}
  f:ForEachProperty(function(p) names[#names+1]=p:GetFName():ToString() end)
  local shape=table.concat(names,'|')
  for i,s in ipairs(expected)do if shape==s then return i end end
  error('Unsupported native function shape: '..path..' ['..shape..']')
 end
 function M.slotName(index,demo,backup,suspend,suspendIndex,backupIndex)
  if not slotArity then
   slotArity=parameters('/Script/QueensDomain.BlueprintUtils:GetSaveSlotName',{
    'SlotIndex|bForceDemoName|bBackup|bSuspend|SuspendIndex|ReturnValue',
    'SlotIndex|bForceDemoName|bBackup|bSuspend|SuspendIndex|BackupIndex|ReturnValue'})
  end
  local u=StaticFindObject('/Script/QueensDomain.BlueprintUtils'):GetCDO()
  if slotArity==2 then return u:GetSaveSlotName(index,demo,backup,suspend,suspendIndex,backupIndex or 0):ToString()end
  return u:GetSaveSlotName(index,demo,backup,suspend,suspendIndex):ToString()
 end
 function M.openPause(player)
  if not pauseArity then
   local f=StaticFindObject('/Game/Player/FS_PlayerChar.FS_PlayerChar_C:OpenPauseMenu')
   assert(f and f:IsValid(),'Native pause menu unavailable')
   pauseArity=1
   f:ForEachProperty(function(p)if p:GetFName():ToString()=='QuickSubmenuIndex'then pauseArity=2 end end)
  end
  if pauseArity==2 then player:OpenPauseMenu(false,0)else player:OpenPauseMenu(false)end
 end
 return M
end
