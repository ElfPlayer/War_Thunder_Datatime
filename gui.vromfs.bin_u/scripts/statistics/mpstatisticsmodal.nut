from "%scripts/dagui_library.nut" import *

//checked for explicitness
#no-root-fallback
#explicit-this

let { needUseHangarDof } = require("%scripts/viewUtils/hangarDof.nut")
let { is_replay_playing } = require("replays")

local MPStatisticsModal = class extends ::gui_handlers.MPStatistics
{
  sceneBlkName = "%gui/mpStatistics.blk"
  sceneNavBlkName = "%gui/navMpStat.blk"
  shouldBlurSceneBgFn = needUseHangarDof
  keepLoaded = true

  wasTimeLeft = -1
  isFromGame = false
  isWideScreenStatTbl = true
  showAircrafts = true
  isResultMPStatScreen = false

  function initScreen()
  {
    ::set_mute_sound_in_flight_menu(false)
    ::in_flight_menu(true)

    //!!init debriefing
    this.isModeStat = true
    this.isRespawn = true
    this.isSpectate = false
    this.isTeam  = true

    let tblObj1 = this.scene.findObject("table_kills_team1")
    if (tblObj1.childrenCount() == 0)
      this.initStats()

    if (this.gameType & GT_COOPERATIVE)
    {
      this.scene.findObject("team1-root").show(false)
      this.isTeam = false
    }

    this.includeMissionInfoBlocksToGamercard()
    this.setSceneTitle(::getCurMpTitle())
    this.refreshPlayerInfo()

    this.showSceneBtn("btn_back", true)

    this.wasTimeLeft = -1
    this.scene.findObject("stat_update").setUserData(this)
    this.isStatScreen = true
    this.forceUpdate()
    this.updateListsButtons()

    this.updateStats()

    this.showSceneBtn("btn_activateorder", !this.isResultMPStatScreen && ::g_orders.showActivateOrderButton())
    let ordersButton = this.scene.findObject("btn_activateorder")
    if (checkObj(ordersButton))
    {
      ordersButton.setUserData(this)
      ordersButton.inactiveColor = !::g_orders.orderCanBeActivated() ? "yes" : "no"
    }
    this.showMissionResult()
    tblObj1.setValue(0)
    this.scene.findObject("table_kills_team2").setValue(-1)
  }

  function reinitScreen(params)
  {
    this.setParams(params)
    ::set_mute_sound_in_flight_menu(false)
    ::in_flight_menu(true)
    this.forceUpdate()
    if (is_replay_playing())
      this.selectLocalPlayer()
    this.showMissionResult()
  }

  function forceUpdate()
  {
    this.updateCooldown = -1
    this.onUpdate(null, 0.0)
  }

  function onUpdate(_obj, dt)
  {
    let timeLeft = ::get_multiplayer_time_left()
    local timeDif = this.wasTimeLeft - timeLeft
    if (timeDif < 0)
      timeDif = -timeDif
    if (timeDif >= 1 || ((this.wasTimeLeft * timeLeft) < 0))
    {
      this.setGameEndStat(timeLeft)
      this.wasTimeLeft = timeLeft
    }
    this.updateTimeToKick(dt)
    this.updateTables(dt)
  }

  function goBack(_obj)
  {
    if (this.isResultMPStatScreen) {
      this.quitToDebriefing()
      return
    }
    ::in_flight_menu(false)
    if (this.isFromGame)
      ::close_ingame_gui()
    else
      ::gui_handlers.BaseGuiHandlerWT.goBack.bindenv(this)()
  }

  function onApply()
  {
    this.goBack(null)
  }

  function onHideHUD(_obj) {}

  function quitToDebriefing() {
    if (::get_mission_status() == MISSION_STATUS_SUCCESS) {
      ::quit_mission_after_complete()
      return
    }

    let text = loc("flightmenu/questionQuitMission")
    this.msgBox("question_quit_mission", text,
      [
        ["yes", function()
          {
          ::quit_to_debriefing()
          ::interrupt_multiplayer(true)
          ::in_flight_menu(false)
        }],
        ["no"]
      ], "yes", { cancel_fn = @() null })
  }

  function showMissionResult() {
    if (!this.isResultMPStatScreen)
      return

    this.scene.findObject("root-box").bgrStyle = "transparent"
    this.scene.findObject("nav-help").hasMaxWindowSize = "yes"
    this.scene.findObject("flight_menu_bgd").hasMissionResultPadding = "yes"
    this.scene.findObject("btn_back").setValue(loc("flightmenu/btnQuitMission"))
    this.updateMissionResultText()
    ::g_hud_event_manager.subscribe("MissionResult", this.updateMissionResultText, this)
  }

  function updateMissionResultText(_eventData = null) {
    let resultIdx = ::get_mission_status()
    if (resultIdx != MISSION_STATUS_SUCCESS && resultIdx != MISSION_STATUS_FAIL)
      return

    let view = {
      text = loc(resultIdx == MISSION_STATUS_SUCCESS ? "MISSION_SUCCESS" : "MISSION_FAIL")
      resultIdx = resultIdx
      useMoveOut = true
    }

    let nest = this.scene.findObject("mission_result_nest")
    let needShowAnimation = !nest.isVisible()
    nest.show(true)
    if (!needShowAnimation)
      return

    let blk = ::handyman.renderCached("%gui/hud/messageStack/missionResultMessage.tpl", view)
    this.guiScene.replaceContentFromText(nest, blk, blk.len(), this)
    let objTarget = nest.findObject("mission_result_box")
    objTarget.show(true)
    ::create_ObjMoveToOBj(this.scene, this.scene.findObject("mission_result_box_start"),
      objTarget, { time = 0.5, bhvFunc = "elasticSmall" })
  }
}

::gui_handlers.MPStatisticsModal <- MPStatisticsModal

::is_mpstatscreen_active <- function is_mpstatscreen_active() // used from native code
{
  if (!::g_login.isLoggedIn())
    return false
  let curHandler = ::handlersManager.getActiveBaseHandler()
  return curHandler != null && (curHandler instanceof ::gui_handlers.MPStatisticsModal)
}