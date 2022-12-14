from "%scripts/dagui_library.nut" import *

//checked for explicitness
#no-root-fallback
#explicit-this

let { handlerType } = require("%sqDagui/framework/handlerType.nut")

::gui_handlers.RemoteMissionModalHandler <- class extends ::gui_handlers.CampaignChapter {
  wndType = handlerType.MODAL
  sceneBlkName = "%gui/empty.blk"

  mission = null

  function initScreen()
  {
    if (this.mission == null)
      return this.goBack()

    this.gm = ::get_game_mode()
    this.curMission = this.mission
    this.setMission()
  }

  function getModalOptionsParam(optionItems, applyFunc)
  {
    return {
      options = optionItems
      applyAtClose = false
      wndOptionsMode = ::get_options_mode(this.gm)
      owner = this
      applyFunc = applyFunc
      cancelFunc = Callback(function() {
                                ::g_missions_manager.isRemoteMission = false
                                this.goBack()
                              }, this)
    }
  }
}