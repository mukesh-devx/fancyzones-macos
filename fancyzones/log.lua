--- Thin wrapper over hs.logger so every module logs under the same name.
--- Output appears in the Hammerspoon Console (menu bar icon > Console).

local M = {}
local logger

function M.setLevel(level)
  logger = hs.logger.new("fancyzones", level or "info")
end

local function get()
  if not logger then M.setLevel("info") end
  return logger
end

function M.d(...) get().d(...) end
function M.i(...) get().i(...) end
function M.w(...) get().w(...) end
function M.e(...) get().e(...) end

return M
