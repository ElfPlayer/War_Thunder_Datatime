from "%scripts/dagui_library.nut" import *

//checked for explicitness
#no-root-fallback
#explicit-this

let showUnlocksGroupWnd = require("%scripts/unlocks/unlockGroupWnd.nut")
let { handlerType } = require("%sqDagui/framework/handlerType.nut")

::gui_start_battle_tasks_select_new_task_wnd <- function gui_start_battle_tasks_select_new_task_wnd(battleTasksArray = null)
{
  if (!::g_battle_tasks.isAvailableForUser() || ::u.isEmpty(battleTasksArray))
    return

  ::gui_start_modal_wnd(::gui_handlers.BattleTasksSelectNewTaskWnd, {battleTasksArray = battleTasksArray})
}

::gui_handlers.BattleTasksSelectNewTaskWnd <- class extends ::gui_handlers.BaseGuiHandlerWT
{
  wndType = handlerType.MODAL
  sceneBlkName = "%gui/modalSceneWithGamercard.blk"
  sceneTplName = "%gui/unlocks/battleTasksSelectNewTask.tpl"

  battleTasksArray = null
  battleTasksConfigsArray = null

  function getSceneTplView()
  {
    return {
      items = this.getBattleTasksViewData()
    }
  }

  function getSceneTplContainerObj()
  {
    return this.scene.findObject("root-box")
  }

  function getBattleTasksViewData()
  {
    this.battleTasksConfigsArray = ::u.map(this.battleTasksArray, @(task) ::g_battle_tasks.generateUnlockConfigByTask(task))
    return ::u.map(this.battleTasksConfigsArray, @(config) ::g_battle_tasks.generateItemView(config))
  }

  function initScreen()
  {
    let listObj = this.getConfigsListObj()
    if (listObj)
    {
      let currentGameModeId = ::game_mode_manager.getCurrentGameModeId()
      let filteredTasksArray = ::g_battle_tasks.filterTasksByGameModeId(this.battleTasksArray, currentGameModeId)

      local index = 0
      if (filteredTasksArray.len())
        index = this.battleTasksArray.findindex(@(task) filteredTasksArray[0].id == task.id) ?? 0

      listObj.setValue(index)
    }
  }

  function getCurrentConfig()
  {
    let listObj = this.getConfigsListObj()
    if (listObj)
      return this.battleTasksConfigsArray[listObj.getValue()]

    return null
  }

  function onSelectTask(_obj)
  {
    let config = this.getCurrentConfig()
    let taskObj = this.getCurrentTaskObj()

    ::showBtn("btn_reroll", false, taskObj)
    this.showSceneBtn("btn_requirements_list", ::show_console_buttons && this.isConfigHaveConditions(config))
  }

  function onSelect(_obj)
  {
    let config = this.getCurrentConfig()
    if (!config)
      return

    let blk = ::DataBlock()
    blk.addStr("mode", "accept")
    blk.addStr("unlockName", config.id)

    let taskId = ::char_send_blk("cln_management_personal_unlocks", blk)
    ::g_tasker.addTask(taskId,
      {showProgressBox = true},
      Callback(function() {
          this.goBack()
          ::broadcastEvent("BattleTasksIncomeUpdate")
        }, this)
    )
  }

  function isConfigHaveConditions(config)
  {
    return getTblValue("names", config, []).len() != 0
  }

  function onViewBattleTaskRequirements()
  {
    let config = this.getCurrentConfig()
    if (!this.isConfigHaveConditions(config))
      return

    let awardsList = ::u.map(config.names,
      @(id) ::build_log_unlock_data(
        ::build_conditions_config(
          ::g_unlocks.getUnlockById(id)
        )
      )
    )

    showUnlocksGroupWnd(awardsList, loc("unlocks/requirements"))
  }

  function getConfigsListObj()
  {
    if (checkObj(this.scene))
      return this.scene.findObject("tasks_list")
    return null
  }

  function getCurrentTaskObj()
  {
    let listObj = this.getConfigsListObj()
    if (!checkObj(listObj))
      return null

    let value = listObj.getValue()
    if (value < 0 || value >= listObj.childrenCount())
      return null

    return listObj.getChild(value)
  }

  function onTaskReroll(_obj) {}
}