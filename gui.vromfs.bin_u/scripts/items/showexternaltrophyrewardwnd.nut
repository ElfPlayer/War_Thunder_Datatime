
//checked for explicitness
#no-root-fallback
#explicit-this

from "%scripts/dagui_library.nut" import *
let { get_time_msec } = require("dagor.time")
let { removeUserstatItemRewardToShow } = require("%scripts/userstat/userstatItemsRewards.nut")
let { addListenersWithoutEnv } = require("%sqStdLibs/helpers/subscriptions.nut")

//this module collect all prizes from userlogs if chest has prizes with auto consume prizes and show trophy window

const MAX_DELAYED_TIME_MS = 30000

let delayedTrophies = persist("delayedTrophies", @() [])

let function showTrophyWnd(config) {
  let { trophyItemDefId, rewardWndConfig } = config
  ::gui_start_open_trophy(rewardWndConfig.__merge({
    [ trophyItemDefId ] = config?.receivedPrizes ?? config.expectedPrizes
  }))
  removeUserstatItemRewardToShow(trophyItemDefId)
}

let function checkRecivedAllPrizesAndShowWnd(config) {
  let { trophyItemDefId, expectedPrizes, time = -1, } = config
  let receivedPrizes = "receivedPrizes" in config ? clone config.receivedPrizes : []
  let notReceivedPrizes = []
  let userLogs = ::getUserLogsList({
    show = [ EULT_OPEN_TROPHY ]
    checkFunc = @(userLog) expectedPrizes.findvalue(
      @(p) p.itemId == (p.isInternalTrophy ? userLog?.body.trophyItemId : userLog?.body.itemId)
    ) != null
  })
  foreach (prize in expectedPrizes) {
    if (!prize.needCollectRewards) {
      receivedPrizes.append(prize)
      continue
    }

    let prizeUserlogs = userLogs.filter(@(userLog) prize.itemId
      == (prize.isInternalTrophy ? userLog?.trophyItemId : userLog?.itemId))
    if (prizeUserlogs.len() == 0) {
      notReceivedPrizes.append(prize)
      continue
    }

    foreach (userLog in prizeUserlogs)
      receivedPrizes.append(userLog.__merge({ itemDefId = trophyItemDefId }))
  }

  if (time != -1 && (time + MAX_DELAYED_TIME_MS < get_time_msec())) {
    receivedPrizes.extend(notReceivedPrizes)
    notReceivedPrizes.clear()
  }

  config = config.__merge({ expectedPrizes = notReceivedPrizes, receivedPrizes })
  if (notReceivedPrizes.len() > 0)
    return config

  showTrophyWnd(config)
  return null
}

let function showExternalTrophyRewardWnd(config) {
  if (config.expectedPrizes.findvalue(@(p) p.needCollectRewards) == null) {
    showTrophyWnd(config)
    return
  }
  config = checkRecivedAllPrizesAndShowWnd(config)
  if (config == null)
    return

  delayedTrophies.append(config.__merge({ time = get_time_msec() }))
}

let function checkShowExternalTrophyRewardWnd() {
  if (!::isInMenu())
    return

  foreach (idx, trophyConfig in delayedTrophies) {
    let config = checkRecivedAllPrizesAndShowWnd(trophyConfig)
    if (config == null) {
      delayedTrophies.remove(idx)
      return
    }

    delayedTrophies[idx] = config
  }
}

addListenersWithoutEnv({
  SignOut = @(_p) delayedTrophies.clear()
})

return {
  showExternalTrophyRewardWnd
  checkShowExternalTrophyRewardWnd
}