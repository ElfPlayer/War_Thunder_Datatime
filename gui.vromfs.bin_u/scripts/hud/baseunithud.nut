from "%scripts/dagui_library.nut" import *

//checked for explicitness
#no-root-fallback
#explicit-this

let { handlerType } = require("%sqDagui/framework/handlerType.nut")
let { getHasCompassObservable } = require("hudCompassState")
let { stashBhvValueConfig } = require("%sqDagui/guiBhv/guiBhvValueConfig.nut")

::gui_handlers.BaseUnitHud <- class extends ::gui_handlers.BaseGuiHandlerWT
{
  scene = null
  wndType = handlerType.CUSTOM

  actionBar    = null
  isReinitDelayed = false

  function initScreen() {
    this.actionBar = null
    this.isReinitDelayed = false
  }

  function updatePosHudMultiplayerScore() {
    let multiplayerScoreObj = this.scene.findObject("hud_multiplayer_score")
    if (checkObj(multiplayerScoreObj)) {
      multiplayerScoreObj.setValue(stashBhvValueConfig([{
        watch = getHasCompassObservable()
        updateFunc = @(obj, value) obj.top = value ? "0.065@scrn_tgt" : "0.015@scrn_tgt"
      }]))
    }
  }

  function onEventControlsPresetChanged(_p) {
    this.isReinitDelayed = true
  }
  function onEventControlsChangedShortcuts(_p) {
    this.isReinitDelayed = true
  }
  function onEventControlsChangedAxes(_p) {
    this.isReinitDelayed = true
  }

  function onEventShowHud(_p) {
    if (this.isReinitDelayed)
    {
      this.actionBar?.reinit(true)
      this.isReinitDelayed = false
    }
  }
}
