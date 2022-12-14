from "%scripts/dagui_library.nut" import *
//checked for explicitness
#no-root-fallback
#explicit-this

let subscriptions = require("%sqStdLibs/helpers/subscriptions.nut")
let { isUnlockVisible } = require("%scripts/unlocks/unlocksModule.nut")

const CHAPTER_NAME = "worldwar"

local cacheArray = {}
local isCacheValid = false

local function invalidateUnlocksCache() {
  isCacheValid = false
  ::ww_event("UnlocksCacheInvalidate")
}

subscriptions.addListenersWithoutEnv({
  UnlocksCacheInvalidate = @(_p) invalidateUnlocksCache()
})

local function getWwUnlocksForCash() {
  local chapter = ""
  local res = []
  foreach(unlock in ::g_unlocks.getAllUnlocksWithBlkOrder())
  {
    local newChapter = unlock?.chapter ?? ""
    if (newChapter != "")
      chapter = newChapter

    if (chapter != CHAPTER_NAME || !isUnlockVisible(unlock))
      continue

    if (!unlock?.needShowInWorldWarMenu)
      continue

    if (unlock?.showAsBattleTask || ::BattleTasks.isBattleTask(unlock))
      continue

    res.append(unlock)
  }

  return res
}

local function validateCache() {
  if (isCacheValid)
    return

  isCacheValid = true
  cacheArray = getWwUnlocksForCash()
}

local function getAllUnlocks() {
  validateCache()
  return cacheArray
}

return {
  getAllUnlocks = getAllUnlocks
  unlocksChapterName = CHAPTER_NAME
  invalidateUnlocksCache = invalidateUnlocksCache
}