-- Library book slots are shared world state. The guest only restores the
-- host's saved book and gate state, without taking or spending a key item.
return function(valid, full)
 local M = {}
 local locked = {}
 local bookClass = 'LIB_BookRecepticle_BP_C'
 local gateClass = 'Lib_TreasureGate_BP_C'

 local function kind(a, name)
  if not valid(a) then return end
  local class = (name or full(a)):match('^([^ ]+) ')
  if class == bookClass or class == 'MementoRecepticle_C' then return 'book' end
  if class == 'AquaDoor_00_C' or class == 'JigekiDoor_BP_C' or class == 'DAquaDoor_01_C' then return 'keyDoor' end
  if class == 'ROS_Treelock_Interaction_BP_C' then return 'orbs' end
  if class == 'AQR_KeyRecepticle_BP_C' or class == 'AQ_OfferingPoint_BP_C' or class == 'SG_Pedestal_TridentKeyReceptacle_C' then return 'book' end
  if class ~= gateClass and class ~= 'Ros_Cage_Gate_BP_C' then return end
  local record = locked[a:GetAddress()]
  if a.SetPuzzleNSD or (record and record.kind == 'gate') then return 'gate' end
 end

 function M.hostOnly(a)
  return kind(a) ~= nil
 end

 function M.lock(a, name)
  local target = kind(a, name)
  if not target then return end
  local address = a:GetAddress()
  local record = locked[address]
  if not record or not valid(record.actor) then
   record = {actor = a, kind = target}
   if target == 'book' then record.disabled = a.InteractIsDisabled end
   locked[address] = record
  end
  if target == 'gate' then
   -- Native presentation of the host's gate must not write quest progress.
   a.SetPuzzleNSD = false
   return
  end
  if target == 'book' then a.InteractIsDisabled = true end
  record.boxes = record.boxes or {}
  local fields = target == 'orbs' and {'InteractBox0','InteractBox1','InteractBox2'} or {'InteractBox'}
  for _,field in ipairs(fields) do
   local box = a[field]
   if valid(box) then
    local collision = box:GetCollisionEnabled()
    if record.boxes[field] == nil then record.boxes[field] = collision end
    if collision ~= 0 then box:SetCollisionEnabled(0) end
   end
  end
 end

 function M.reset()
  for _, record in pairs(locked) do
   local a = record.actor
   if valid(a) then
    if record.kind == 'gate' then
     a.SetPuzzleNSD = true
    else
     if record.kind == 'book' then a.InteractIsDisabled = record.disabled end
     for field,collision in pairs(record.boxes or {}) do
      if valid(a[field]) then a[field]:SetCollisionEnabled(collision) end
     end
    end
   end
  end
  locked = {}
 end

 return M
end
