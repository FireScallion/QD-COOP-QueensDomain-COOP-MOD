-- Reconcile persistent reward effects without replaying latent pickup montages.
-- Verified from the installed Default_Dagger_Visuals and projectile blueprints.
return function(valid,log)
 local M={}
 function M.reconcile(game,player)
  local s=game.ActiveSaveSlot
  -- Also invalidate already-built equipment/stat caches after late restoration.
  player:RefreshEquippedItemEffects()
  local stats=StaticFindObject('/Game/LD45/Blueprints/StatCachingUtils.Default__StatCachingUtils_C')
  assert(valid(stats),'Stat cache utility unavailable')
  stats['Recache All Stats (Except HP)'](stats,player)
  local acid=LoadAsset('/Game/Items/KeyItems/AcidVial/AcidVial.AcidVial')
  assert(valid(acid),'AcidVial asset unavailable')
  if not s.InventoryContents:Contains(acid)or s.InventoryContents:Find(acid):get()<=0 then return end
  -- Projectile GetDamage reads this character's inventory directly. There is
  -- no replacement dagger item and no bottle consumption to manufacture here.
  -- An already-spawned dagger, however, only refreshes on native montage notify.
  local refreshed=false
  local v=player.Daggervisuals
  if valid(v)then
   local c=LoadAsset('/Game/Items/Weapons/Daggers/Default/Default_Dagger_Visuals.Default_Dagger_Visuals_C')
   assert(valid(c),'Default dagger class unavailable')
   if v:IsA(c)then v:RefreshAcidVialState();refreshed=true end
  end
  log('REWARD EFFECTS reconciled AcidVial; inventory unchanged; existing dagger refreshed='..tostring(refreshed))
 end
 return M
end
