require ecs
require app
require net
require Unit
require DagorMath
require DagorDataBlock
require DagorRandom
require IGroundModel
require dm
require DmFire
require WTDamageModel
require WarShipModel
require %game.events
require %game.unit_events
require %game.extinguish_system_events
require %game.extinguish_system_common


def fire_system_stop_single_burn(eid : EntityId; var fire_damage : FireDamageComponent&; fire_id : int)
  if fire_id >= 0 && fire_id < length(fire_damage.data)
    sendEvent(eid, [[EventOnStopSingleBurn fireId=fire_id, initiatorId=fire_damage.data[fire_id].initiatorId]])
    fire_damage.data[fire_id].startTime = -1.0lf;
    fire_damage.data[fire_id].initiatorId = -1u;


// ---------------------------- extinguish system update -------------------------------

[es(no_order)]
def extinguish_system_update_es(act : UpdateStageInfoAct;
                                eid : EntityId;
                                uid : int;
                                extinguish_system_penalty_without_mod : bool;
                                fire_damage__isBurn : bool;
                                extinguish_system_is_assisting : bool;
                                extinguish_system_extinguisher_count : int;
                                extinguish_system_extinguisher_count_max : int;
                                var extinguish_system_extinguish_time_start : float&;
                                var extinguish_system_extinguish_time_end : float&;
                                extinguish_system_extinguisher_time_min : float;
                                var extinguish_system_crew_busy_time_end : float&;
                                var extinguish_system_next_extinguisher_time : float&;
                                var fire_system_require_net_sync : bool&;
                                var fire_damage : FireDamageComponent&)
  let unit = get_unit(uid)
  if unit == null || unit.isDelayed || !unit.isAuthority
    return

  let gm = unit |> as_gm()
  let total_time = float(get_app().usefulTotalTime)

  if fire_damage__isBurn || extinguish_system_is_assisting
    if extinguish_system_crew_busy_time_end > 0.0 && extinguish_system_crew_busy_time_end < total_time
      extinguish_system_crew_busy_time_end = -1.0f
      sendEvent(eid, [[EventExtinguishSystemNotifyCrewBusy busy=false]])
      fire_system_require_net_sync = true

    // handle warships (TODO: move it to other system)
    if unit.isShip
      if extinguish_system_extinguish_time_end > extinguish_system_extinguish_time_start
        let time_to_extinguish = safediv(extinguish_system_extinguisher_time_min, gm.crewExtinguishSpeedMultiplier);
        var current_time_to_extinguish = 0.0;
        if (is_extinguisher_active(fire_damage__isBurn, extinguish_system_is_assisting, extinguish_system_extinguish_time_end) &&
            extinguish_system_extinguish_time_end > extinguish_system_extinguish_time_start)
          current_time_to_extinguish = extinguish_system_extinguish_time_end - extinguish_system_extinguish_time_start

        if time_to_extinguish + 1.0 < current_time_to_extinguish
          extinguish_system_extinguish_time_start = total_time - time_to_extinguish * (
            (total_time - extinguish_system_extinguish_time_start) / current_time_to_extinguish)
          extinguish_system_extinguish_time_end = extinguish_system_extinguish_time_start + time_to_extinguish
        else
          extinguish_system_extinguish_time_end += time_to_extinguish - current_time_to_extinguish

        if abs(time_to_extinguish - current_time_to_extinguish) > .5f
          fire_system_require_net_sync = true

    if 0.0 < extinguish_system_extinguish_time_end && extinguish_system_extinguish_time_end < total_time
      let has_mod = has_extinguisher_mod(gm, extinguish_system_extinguisher_count, extinguish_system_extinguisher_count_max)
      let assistee_eid = unit.extinguishAssisteeEid
      let assistant_eid = unit.extinguishAssistantEid
      assert((assistee_eid != INVALID_ENTITY_ID) == extinguish_system_is_assisting) // has assistee doesnt match is assisting state
      assert(assistant_eid == INVALID_ENTITY_ID || !extinguish_system_is_assisting) // has assistant but assisting someone

      sendEvent(eid, [[EventExtinguishSystemStopBurnWithExtinguisher
        targetEid = assistee_eid != INVALID_ENTITY_ID ? assistee_eid : eid,
        hasMod = has_mod,
        withPenalty = extinguish_system_penalty_without_mod
      ]])
      sendEvent(eid, [[EventExtinguishSystemTurnOffExtinguisher]])
      if assistant_eid == INVALID_ENTITY_ID
        sendEvent(eid, [[EventExtinguishSystemSpendExtinguisher]])

    // update underwater
    if !is_extinguisher_active(fire_damage__isBurn, extinguish_system_is_assisting, extinguish_system_extinguish_time_end)
      for fire_data in fire_damage.data
        if fire_data.startTime < 0.0lf
          continue
        let is_underwater = is_fire_emitter_underwater(eid, fire_data)
        if is_underwater
          if fire_data.underwaterTimer < 0.0f
            fire_data.underwaterTimer = get_fire_params(fire_data.fireParamsId).underwaterExtinguishTime
        else
          fire_data.underwaterTimer = -1.0f

        if fire_data.underwaterTimer > 0.0f
          fire_data.underwaterTimer -= act.dt
          if fire_data.underwaterTimer <= 0.0f
            fire_system_stop_single_burn(eid, fire_damage, fire_data.id)
            fire_system_require_net_sync = true

  if extinguish_system_next_extinguisher_time < total_time && extinguish_system_next_extinguisher_time > 0.0f
    extinguish_system_next_extinguisher_time = -1.0f
    fire_system_require_net_sync = true


// ---------------------------- extinguish init & reset --------------------------------

def load_extinguisher_mod_blk(blk : DataBlock&;
                              var unit : Unit?;
                              var extinguish_system_auto_extinguisher : bool&;
                              var extinguish_system_extinguisher_count : int&;
                              var extinguish_system_extinguisher_count_max : int&;
                              var extinguish_system_cooldown : float&;
                              var extinguish_system_crew_busy_time : float&;
                              var extinguish_system_extinguisher_time_min : float&;
                              var extinguish_system_extinguisher_time_max : float&;
                              extinguish_system_penalty_without_mod : bool)
  var gm = unit |> as_gm()
  if gm != null && extinguish_system_extinguisher_count_max == 0
    extinguish_system_extinguisher_count_max = gm.extinguisher.count

  extinguish_system_auto_extinguisher = blk |> datablock_getBool("automaticExtinguisher", extinguish_system_auto_extinguisher);
  extinguish_system_extinguisher_count_max = blk |> datablock_getInt("extinguisherActivationCount", extinguish_system_extinguisher_count_max);

  var extinguisher_reduction_time = 0.0f;
  var extinguisher_activation_additional_count = 0;

  let additional_count_name_id = blk |> datablock_getNameId("extinguisherActivationAdditionalCount");
  let extinguisher_reduction_time_name_id = blk |> datablock_getNameId("extinguisherReductionTime");
  let cooldown_name_id = blk |> datablock_getNameId("extinguisherCooldown");

  if (additional_count_name_id >= 0 || extinguisher_reduction_time_name_id >= 0 || cooldown_name_id >= 0)
    for i in 0u..blk.paramCount
      let param_name_id = blk |> datablock_getParamNameId(i)
      let param_type = blk |> datablock_getParamType(i)

      if param_name_id == additional_count_name_id && param_type == int(DataBlockParamType TYPE_INT)
        extinguisher_activation_additional_count += blk |> datablock_getInt(int(i))
      elif param_name_id == extinguisher_reduction_time_name_id && param_type == int(DataBlockParamType TYPE_REAL)
        extinguisher_reduction_time += blk |> datablock_getReal(int(i));
      elif param_name_id == cooldown_name_id
        extinguish_system_cooldown = blk |> datablock_getReal(int(i));

  if (extinguish_system_extinguisher_count_max > 0)
    extinguish_system_extinguisher_count_max += extinguisher_activation_additional_count;

  let time_min = blk |> datablock_getReal("extinguisherMinTime", -1.0f);
  let time_max = blk |> datablock_getReal("extinguisherMaxTime", -1.0f);
  if time_min > 0.0f && time_max >= 0.0f
    extinguish_system_extinguisher_time_min = max(time_min - extinguisher_reduction_time, 0.0f);
    extinguish_system_extinguisher_time_max = max(time_max - extinguisher_reduction_time, 0.0f);
    if (extinguish_system_extinguisher_time_max >= extinguish_system_extinguisher_time_min)
      extinguish_system_extinguisher_time_max = extinguish_system_extinguisher_time_min
  extinguish_system_crew_busy_time = blk |> datablock_getReal("extinguisherCrewBusyTime", extinguish_system_crew_busy_time);

  if gm != null
    extinguish_system_extinguisher_count = min(gm.extinguisher.count, extinguish_system_extinguisher_count_max);
  if (extinguish_system_extinguisher_count_max < 0)
    extinguish_system_extinguisher_count = 0;
  if (extinguish_system_extinguisher_time_max <= extinguish_system_extinguisher_time_min)
    extinguish_system_extinguisher_time_max = extinguish_system_extinguisher_time_min

  if (gm != null)
    gm.haveExtinguish = is_extinguisher_available(gm,
      extinguish_system_extinguisher_count,
      extinguish_system_extinguisher_count_max,
      extinguish_system_penalty_without_mod
    )


[es]
def extinguish_system_init_handle_es(evt : CmdInitComponent;
                                     uid : int;
                                     var extinguish_system_penalty_without_mod : bool&;
                                     var extinguish_system_auto_extinguisher : bool&;
                                     var extinguish_system_extinguisher_count : int&;
                                     var extinguish_system_extinguisher_count_max : int&;
                                     var extinguish_system_cooldown : float&;
                                     var extinguish_system_crew_busy_time : float&;
                                     var extinguish_system_extinguisher_time_min : float&;
                                     var extinguish_system_extinguisher_time_max : float&)
  var unit = get_unit(uid)
  var gm = unit |> as_gm()
  assert(unit != null)
  if unit == null
    return

  extinguish_system_extinguisher_count = 0
  extinguish_system_penalty_without_mod = false
  extinguish_system_auto_extinguisher = false
  extinguish_system_cooldown = 0.0f
  extinguish_system_crew_busy_time = 5.0f
  extinguish_system_extinguisher_time_min = 0.0f
  extinguish_system_extinguisher_time_max = 0.0f
  if gm != null
    gm.haveExtinguish = false;

  if unit.isShip
    *evt.modelBlk |> datablock_get_block("shipDamageControl") <| $(ship_dc_blk)
      extinguish_system_penalty_without_mod = ship_dc_blk |> datablock_getBool("shipDamageControlEnabled", false)
      ship_dc_blk |> datablock_get_block("defaultExtinguisher") <| $(blk)
        load_extinguisher_mod_blk(blk,
          unit,
          extinguish_system_auto_extinguisher,
          extinguish_system_extinguisher_count,
          extinguish_system_extinguisher_count_max,
          extinguish_system_cooldown,
          extinguish_system_crew_busy_time,
          extinguish_system_extinguisher_time_min,
          extinguish_system_extinguisher_time_max,
          extinguish_system_penalty_without_mod)


[es]
def extinguish_system_init_mod_handle_es(evt : EventUnitInitModification;
                                         uid : int;
                                         extinguish_system_penalty_without_mod : bool;
                                         var extinguish_system_auto_extinguisher : bool&;
                                         var extinguish_system_extinguisher_count : int&;
                                         var extinguish_system_extinguisher_count_max : int&;
                                         var extinguish_system_cooldown : float&;
                                         var extinguish_system_crew_busy_time : float&;
                                         var extinguish_system_extinguisher_time_min : float&;
                                         var extinguish_system_extinguisher_time_max : float&)
  if evt.modType != "extinguisher"
    return

  var unit = get_unit(uid)
  var gm = unit |> as_gm()
  assert(unit != null)
  if unit == null
    return

  extinguish_system_extinguisher_count_max = gm != null && gm.extinguisher.isAvailable ? (unit.isShip ? -1 : 0) : 0

  load_extinguisher_mod_blk(*evt.blk,
    unit,
    extinguish_system_auto_extinguisher,
    extinguish_system_extinguisher_count,
    extinguish_system_extinguisher_count_max,
    extinguish_system_cooldown,
    extinguish_system_crew_busy_time,
    extinguish_system_extinguisher_time_min,
    extinguish_system_extinguisher_time_max,
    extinguish_system_penalty_without_mod)


[es]
def extinguish_system_repair_handle_es(evt : EventUnitRepair;
                                       eid : EntityId;
                                       var extinguish_system_extinguish_time_start : float&;
                                       var extinguish_system_extinguish_time_end : float&;
                                       var extinguish_system_crew_busy_time_end : float&;
                                       var extinguish_system_is_assisting : bool&;
                                       var fire_system_require_net_sync : bool&)
  extinguish_system_extinguish_time_start = -1.0f
  extinguish_system_extinguish_time_end = -1.0f
  extinguish_system_crew_busy_time_end = -1.0f
  extinguish_system_is_assisting = false
  fire_system_require_net_sync = true
  sendEvent(eid, [[CmdStopBurn]])
  sendEvent(eid, [[EventExtinguishSystemNotifyCrewBusy busy=false]])
  sendEvent(eid, [[EventFireSystemStopBurn]])


[es]
def extinguish_system_respawn_handle_es(evt : EventUnitRespawn;
                                        eid : EntityId;
                                        uid : int;
                                        var extinguish_system_extinguisher_count : int&;
                                        extinguish_system_extinguisher_count_max : int;
                                        var extinguish_system_extinguish_time_start : float&;
                                        var extinguish_system_extinguish_time_end : float&;
                                        var extinguish_system_crew_busy_time_end : float&;
                                        var extinguish_system_next_extinguisher_time : float&;
                                        var extinguish_system_is_assisting : bool&;
                                        var fire_system_require_net_sync : bool&;
                                        var fire_damage : FireDamageComponent&)
  fire_damage.data |> clear()
  fire_damage.nextUpdateTime = -1.0lf

  let unit = get_unit(uid)
  let gm = unit |> as_gm()
  var extinguisher_count = -1
  if gm != null && !unit.isDelayed
    gm.extinguisher |> reinit_expendable_modification()
    extinguisher_count = gm.extinguisher.count

  if extinguisher_count >= 0
    extinguish_system_extinguisher_count = min(extinguish_system_extinguisher_count_max, extinguisher_count)
  if extinguish_system_extinguisher_count_max < 0
    extinguish_system_extinguisher_count = 0

  extinguish_system_extinguish_time_start = -1.0f
  extinguish_system_extinguish_time_end = -1.0f
  extinguish_system_crew_busy_time_end = -1.0f
  extinguish_system_next_extinguisher_time = -1.0f
  extinguish_system_is_assisting = false
  fire_system_require_net_sync = true
  sendEvent(eid, [[EventExtinguishSystemNotifyCrewBusy busy=false]])
  sendEvent(eid, [[EventFireSystemStopBurn]])


// ---------------------------- extinguish other events --------------------------------

[es]
def extinguish_system_activate_handle_es(evt : EventExtinguishSystemSetActive;
                                         eid : EntityId;
                                         uid : int;
                                         fire_damage__isBurn : bool;
                                         var extinguish_system_extinguish_time_start : float&;
                                         var extinguish_system_extinguish_time_end : float&;
                                         var extinguish_system_crew_busy_time_end : float&;
                                         var extinguish_system_is_assisting : bool&;
                                         var fire_system_require_net_sync : bool&)
  let unit = get_unit(uid)
  if unit == null
    return

  let ship = unit |> as_ship()
  if ship == null || !ship.isVeryFewCrew
    if evt.active
      sendEventImmediate(eid, [[EventExtinguishSystemActivateExtinguisher assisteeId=INVALID_ENTITY_ID]])
    else
      if !unit.isDelayed && unit.isAuthority && is_extinguisher_active(fire_damage__isBurn, extinguish_system_is_assisting, extinguish_system_extinguish_time_end)
        sendEvent(eid, [[EventExtinguishSystemSpendExtinguisher]])
      extinguish_system_extinguish_time_start = -1.0f
      extinguish_system_extinguish_time_end = -1.0f
      extinguish_system_crew_busy_time_end = -1.0f
      extinguish_system_is_assisting = false
      fire_system_require_net_sync = true
      sendEvent(eid, [[EventExtinguishSystemNotifyCrewBusy busy=false]])


[es]
def extinguish_system_activate_extinguisher_handle_es(evt : EventExtinguishSystemActivateExtinguisher;
                                                      eid : EntityId;
                                                      uid : int;
                                                      fire_damage__isBurn : bool;
                                                      var extinguish_system_is_assisting : bool&;
                                                      extinguish_system_penalty_without_mod : bool;
                                                      extinguish_system_extinguisher_count : int;
                                                      extinguish_system_extinguisher_count_max : int;
                                                      extinguish_system_extinguisher_time_min : float;
                                                      extinguish_system_extinguisher_time_max : float;
                                                      var extinguish_system_extinguish_time_start : float&;
                                                      var extinguish_system_extinguish_time_end : float&;
                                                      extinguish_system_next_extinguisher_time : float;
                                                      var extinguish_system_crew_busy_time_end : float&;
                                                      extinguish_system_crew_busy_time : float;
                                                      var fire_system_require_net_sync : bool&;
                                                      fire_damage : FireDamageComponent&)
  let is_assisting = evt.assisteeId != INVALID_ENTITY_ID
  let is_burning = fire_damage__isBurn
  if (is_burning && is_assisting) || (!is_burning && !is_assisting)
    return

  let unit = get_unit(uid)
  if unit == null || unit.isDelayed
    return
  let gm = unit |> as_gm()

  let is_available = is_extinguisher_available(gm, extinguish_system_extinguisher_count, extinguish_system_extinguisher_count_max, extinguish_system_penalty_without_mod)
  let is_active = is_extinguisher_active(is_burning, is_assisting, extinguish_system_extinguish_time_end)
  if (is_available && !is_active && extinguish_system_next_extinguisher_time < 0.0)
    if is_assisting
      query(evt.assisteeId) <| $ [es] (fire_damage : FireDamageComponent&)
        if !can_be_extinguished_with_extinguisher(fire_damage)
          sendEvent(eid, [[EventExtinguishSystemNotifyCantExtinguish]])
    elif !can_be_extinguished_with_extinguisher(fire_damage)
      sendEvent(eid, [[EventExtinguishSystemNotifyCantExtinguish]])
      return

    let total_time = float(get_app().usefulTotalTime)

    if unit.isTank && !is_assisting
      extinguish_system_crew_busy_time_end = max(total_time + extinguish_system_crew_busy_time, extinguish_system_crew_busy_time_end)

    if unit.isAuthority
      var time_to_extinguish = rnd_float(extinguish_system_extinguisher_time_min, extinguish_system_extinguisher_time_max)
      if unit.isShip
        extinguish_system_extinguish_time_end = 1.0f
        time_to_extinguish = safediv(extinguish_system_extinguisher_time_min, gm.crewExtinguishSpeedMultiplier)

      extinguish_system_extinguish_time_start = total_time
      extinguish_system_extinguish_time_end = extinguish_system_extinguish_time_start + time_to_extinguish
      extinguish_system_is_assisting = is_assisting
      fire_system_require_net_sync = true
      sendEvent(eid, [[EventExtinguishSystemNotifyCrewBusy busy=true]])

    sendEvent(eid, [[EventExtinguishSystemOnExtinguisherActivate active=true]])


[es]
def extinguish_system_stop_burn_with_extinguisher_handle_es(evt : EventExtinguishSystemStopBurnWithExtinguisher;
                                                            eid : EntityId;
                                                            var extinguish_system_is_assisting : bool&;
                                                            var extinguish_system_next_extinguisher_time : float&;
                                                            var extinguish_system_last_extinguish_time : float&;
                                                            extinguish_system_cooldown : float;
                                                            var fire_system_require_net_sync : bool&)
  let with_penalty = !evt.hasMod && evt.withPenalty

  var all_extinguished = true
  var continue_extinguishing = false
  if evt.hasMod || with_penalty
    query(evt.targetEid) <| $ [es] (var fire_damage : FireDamageComponent&)
      if with_penalty
        var fireId = -1
        var maxSeverity : float = 0.0f
        for fire_data in fire_damage.data
          let fire_params = get_fire_params(fire_data.fireParamsId)
          if fire_params == null || fire_params.extinguisherEffective
            if fire_data.startTime < 0.0lf
              continue
            let severity = fire_data.finalRadius
            if severity > maxSeverity
              fireId = fire_data.id
              maxSeverity = severity
        for fire_data in fire_damage.data
          let fire_params = get_fire_params(fire_data.fireParamsId)
          if fire_data.id == fireId
            fire_system_stop_single_burn(eid, fire_damage, fire_data.id)
            fire_system_require_net_sync = true
          elif fire_data.startTime >= 0.0lf
            all_extinguished = false
            if fire_params == null || fire_params.extinguisherEffective
              continue_extinguishing = true
      else
        for fire_data in fire_damage.data
          let fire_params = get_fire_params(fire_data.fireParamsId)
          if fire_params == null || fire_params.extinguisherEffective
            fire_system_stop_single_burn(eid, fire_damage, fire_data.id)
            fire_system_require_net_sync = true
          else
            all_extinguished = false
  else
    all_extinguished = false

  if !continue_extinguishing
    let total_time = float(get_app().usefulTotalTime)
    extinguish_system_next_extinguisher_time = total_time + extinguish_system_cooldown
    extinguish_system_last_extinguish_time = total_time
    extinguish_system_is_assisting = false
    sendEvent(eid, [[EventExtinguishSystemNotifyCrewBusy busy=false]])
    sendEvent(evt.targetEid, [[EventExtinguishSystemNotifyExtinghuished]])
  else
    sendEvent(eid, [[EventExtinguishSystemActivateExtinguisher assisteeId=evt.targetEid]])

  if all_extinguished
    sendEvent(evt.targetEid, [[EventFireSystemStopBurn]])


[es]
def extinguish_system_spend_extinguisher_es(evt : EventExtinguishSystemSpendExtinguisher;
                                            uid : int;
                                            var extinguish_system_extinguisher_count : int&;
                                            extinguish_system_extinguisher_count_max : int;
                                            var fire_system_require_net_sync : bool&)
  let unit = get_unit(uid)
  if extinguish_system_extinguisher_count_max > 0 && !unit.isDelayed && unit.isAuthority
    if extinguish_system_extinguisher_count > 0
      --extinguish_system_extinguisher_count
    let gm = unit |> as_gm()
    if gm != null
      gm.extinguisher |> spend_expendable_modification()
    fire_system_require_net_sync = true


[es]
def extinguish_system_extinguish_by_ally_handle_es(evt : EventExtinguishSystemExtinguishByAlly;
                                                   eid : EntityId;
                                                   uid : int;
                                                   fire_damage__isBurn : bool;
                                                   extinguish_system_is_assisting : bool;
                                                   extinguish_system_penalty_without_mod : bool;
                                                   extinguish_system_extinguisher_count : int;
                                                   extinguish_system_extinguisher_count_max : int;
                                                   var extinguish_system_extinguish_time_start aka extinguish_system_extinguish_time_start_host : float&;
                                                   var extinguish_system_extinguish_time_end aka extinguish_system_extinguish_time_end_host : float&;
                                                   extinguish_system_next_extinguisher_time : float;
                                                   var fire_system_require_net_sync : bool&;
                                                   fire_damage : FireDamageComponent&)
  let unit = get_unit(uid)
  if unit == null || unit.isDelayed
    return
  let gm = unit |> as_gm()
  let is_burning = fire_damage__isBurn

  if (is_burning &&
      !is_extinguisher_available(gm, extinguish_system_extinguisher_count, extinguish_system_extinguisher_count_max, extinguish_system_penalty_without_mod) &&
      !is_extinguisher_active(is_burning, extinguish_system_is_assisting, extinguish_system_extinguish_time_end) &&
      extinguish_system_next_extinguisher_time < 0.0)
    if !can_be_extinguished_with_extinguisher(fire_damage)
      return

    if unit == null
      return

    if unit.isAuthority
      query(evt.assistantId) <| $ [es] (extinguish_system_extinguish_time_start : float; extinguish_system_extinguish_time_end : float)
        extinguish_system_extinguish_time_start_host = extinguish_system_extinguish_time_start
        extinguish_system_extinguish_time_end_host = extinguish_system_extinguish_time_end
    sendEvent(eid, [[EventExtinguishSystemNotifyCrewBusy busy=true]])
    sendEvent(eid, [[EventExtinguishSystemOnExtinguisherActivate active=true]])
    fire_system_require_net_sync = true


[es]
def extinguish_system_turn_off_extinguisher_handle_es(evt : EventExtinguishSystemTurnOffExtinguisher;
                                                      eid : EntityId;
                                                      var extinguish_system_is_assisting : bool&;
                                                      var extinguish_system_extinguish_time_start : float&;
                                                      var extinguish_system_extinguish_time_end : float&)
  if extinguish_system_extinguish_time_end > 0.0f
    extinguish_system_extinguish_time_start = -1.0f
    extinguish_system_extinguish_time_end = -1.0f
    extinguish_system_is_assisting = false
    sendEvent(eid, [[EventExtinguishSystemOnExtinguisherActivate active=false]])


[es]
def extinguish_system_add_extinguisher_count_handle_es(evt : EventExtinguishSystemAddExtinguisherCount;
                                                       var extinguish_system_extinguisher_count : int&;
                                                       var extinguish_system_extinguisher_count_max : int&)
  extinguish_system_extinguisher_count = min(255, extinguish_system_extinguisher_count + evt.count)
  extinguish_system_extinguisher_count_max = extinguish_system_extinguisher_count // <--- ???


// -------------------------------- fire net sync --------------------------------------

[es(after=extinguish_system_update_es, tag=server)]
def fire_system_net_sync_update_es(act : UpdateStageInfoAct;
                                   eid : EntityId;
                                   extinguish_system_extinguisher_count : int;
                                   extinguish_system_is_assisting : bool;
                                   extinguish_system_crew_busy_time_end : float;
                                   extinguish_system_extinguish_time_end : float;
                                   extinguish_system_next_extinguisher_time : float;
                                   var fire_system_require_net_sync : bool&;
                                   fire_damage__isBurn : bool;
                                   fire_damage : FireDamageComponent&)
  if !fire_system_require_net_sync
    return
  fire_system_require_net_sync = false

  let total_time = float(get_app().usefulTotalTime)
  using() <| $(var data : IntList#)
    data |> reserve(length(fire_damage.data) * 2)
    for fire_data in fire_damage.data
      let is_burning = fire_data.startTime >= 0.0lf
      if is_burning
        data |> push(fire_data.partNo)
        data |> push(fire_data.fireParamsId)

    send_net_event(eid, [[EventFireSystemNetSync
      isBurning = fire_damage__isBurn,
      extinguisherCount = extinguish_system_extinguisher_count,
      crewBusyRemainingTime = is_crew_busy(fire_damage__isBurn, extinguish_system_is_assisting, extinguish_system_crew_busy_time_end) ? extinguish_system_crew_busy_time_end - total_time : -1.0f,
      extinguisherRemainingTime = is_extinguisher_active(fire_damage__isBurn, extinguish_system_is_assisting, extinguish_system_extinguish_time_end) ? extinguish_system_extinguish_time_end - total_time : -1.0f,
      timeToNextExtinguisher = extinguish_system_next_extinguisher_time,
      data=ecs_addr(data)
    ]])


[es(tag=netClient)]
def fire_system_net_sync_handle_es(evt : EventFireSystemNetSync;
                                   eid : EntityId;
                                   extinguish_system_is_assisting : bool;
                                   var extinguish_system_crew_busy_time_end : float&;
                                   var extinguish_system_extinguish_time_start : float&;
                                   var extinguish_system_extinguish_time_end : float&;
                                   var extinguish_system_next_extinguisher_time : float&;
                                   var extinguish_system_extinguisher_count : int&;
                                   var fire_damage__isBurn : bool&;
                                   var fire_damage : FireDamageComponent&)
  let total_time = float(get_app().usefulTotalTime)
  let was_burning = fire_damage__isBurn;
  let was_extinguisher_active = is_extinguisher_active(fire_damage__isBurn, extinguish_system_is_assisting, extinguish_system_extinguish_time_end)

  fire_damage__isBurn = evt.isBurning;
  extinguish_system_extinguisher_count = evt.extinguisherCount;
  extinguish_system_crew_busy_time_end = evt.crewBusyRemainingTime > 0.0 ? evt.crewBusyRemainingTime + total_time : -1.0f
  extinguish_system_extinguish_time_start = evt.extinguisherRemainingTime > 0.0f ? total_time : 0.0f
  extinguish_system_extinguish_time_end = evt.extinguisherRemainingTime > 0.0f ? evt.extinguisherRemainingTime + total_time : 0.0f
  extinguish_system_next_extinguisher_time = evt.timeToNextExtinguisher

  sendEventImmediate(eid, [[EventExtinguishSystemNotifyCrewBusy busy=is_crew_busy(fire_damage__isBurn, extinguish_system_is_assisting, extinguish_system_crew_busy_time_end)]])
  if !was_extinguisher_active && evt.extinguisherRemainingTime > 0.0f
    sendEvent(eid, [[EventExtinguishSystemOnExtinguisherActivate active=true]])
  if !was_burning && evt.isBurning
    sendEvent(eid, [[EventFireSystemOnStartBurnNoOffender]])
  elif was_burning && !evt.isBurning
    sendEvent(eid, [[EventFireSystemStopBurn]])

  var burning_parts : array<tuple<part_id : int; fire_params_id : int; already_burning : bool>>
  burning_parts |> reserve(length(*evt.data) / 2)
  for i in range(0, length(*evt.data) / 2)
    let part_id = (*evt.data)[i * 2]
    let fire_params_id = (*evt.data)[i * 2 + 1]
    burning_parts |> push([[auto part_id, fire_params_id, false]])

  for fire_data in fire_damage.data
    var fire_found = false
    for part in burning_parts
      if fire_data.partNo == part.part_id
        fire_found = true
        part.already_burning = true
        break
    if !fire_found
      fire_system_stop_single_burn(eid, fire_damage, fire_data.id)

  for part in burning_parts
    if !part.already_burning
      sendEvent(eid, [[EventFireSystemStartSingleBurn partId=part.part_id, fireParamsId=part.fire_params_id]])
