-- Split only receive/presentation state. Local discovery, hooks, capture and
-- retained resources stay shared, regardless of the number of remote players.
return function(owner,keys,create)
 local M={states={}}
 function M.run(id,fn,...)
  local state=M.states[id];if not state then state=create();M.states[id]=state end
  local previous={};for _,k in ipairs(keys)do previous[k]=owner[k];owner[k]=state[k]end
  local result=table.pack(pcall(fn,...))
  for _,k in ipairs(keys)do state[k]=owner[k];owner[k]=previous[k]end
  if not result[1]then error(result[2],0)end
  return table.unpack(result,2,result.n)
 end
 function M.remove(id,cleanup,travel)
  if M.states[id]then M.run(id,cleanup,travel);M.states[id]=nil end
 end
 function M.reset(cleanup,travel)for id in pairs(M.states)do M.remove(id,cleanup,travel)end end
 return M
end
