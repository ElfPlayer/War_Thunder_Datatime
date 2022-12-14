from "%scripts/dagui_library.nut" import *

//checked for explicitness
#no-root-fallback
#explicit-this

let { format } = require("string")
let { calculate_tank_bullet_parameters } = require("unitCalculcation")
let enums = require("%sqStdLibs/helpers/enums.nut")
let stdMath = require("%sqstd/math.nut")
let { WEAPON_TYPE,
        getLinkedGunIdx,
        getWeaponNameByBlkPath } = require("%scripts/weaponry/weaponryInfo.nut")
let { getBulletsList,
        getBulletsSetData,
        getBulletsSearchName,
        getBulletsGroupCount,
        getLastFakeBulletsIndex,
        getModificationBulletsEffect } = require("%scripts/weaponry/bulletsInfo.nut")
let unitTypes = require("%scripts/unit/unitTypesList.nut")
let { UNIT } = require("%scripts/utils/genericTooltipTypes.nut")
let { SINGLE_WEAPON, MODIFICATION, SINGLE_BULLET } = require("%scripts/weaponry/weaponryTooltips.nut")
let { hasUnitAtRank } = require("%scripts/airInfo.nut")
let { shopCountriesList } = require("%scripts/shop/shopCountriesList.nut")
let { isCountryHaveUnitType } = require("%scripts/shop/shopUnitsInfo.nut")
let { getUnitWeapons, getWeaponBlkParams } = require("%scripts/weaponry/weaponryPresets.nut")

local options = {
  types = []
  cache = {
    bySortId = {}
  }

  nestObj = null
  isSaved = false
  targetUnit = null
  setParams = @(unit) this.targetUnit = unit
}

let targetTypeToThreatTypes = {
  [ES_UNIT_TYPE_AIRCRAFT]   = [ ES_UNIT_TYPE_AIRCRAFT, ES_UNIT_TYPE_TANK, ES_UNIT_TYPE_HELICOPTER ],
  [ES_UNIT_TYPE_HELICOPTER] = [ ES_UNIT_TYPE_AIRCRAFT, ES_UNIT_TYPE_TANK, ES_UNIT_TYPE_HELICOPTER ],
  [ES_UNIT_TYPE_TANK] = [ ES_UNIT_TYPE_AIRCRAFT, ES_UNIT_TYPE_TANK, ES_UNIT_TYPE_HELICOPTER ],
  [ES_UNIT_TYPE_SHIP] = [ ES_UNIT_TYPE_SHIP, ES_UNIT_TYPE_BOAT ],
  [ES_UNIT_TYPE_BOAT] = [ ES_UNIT_TYPE_SHIP, ES_UNIT_TYPE_BOAT ],
}

let function getThreatEsUnitTypes()
{
  let targetUnitType = options.targetUnit.esUnitType
  let res = targetTypeToThreatTypes?[targetUnitType] ?? [ targetUnitType ]
  return res.filter(@(e) unitTypes.getByEsUnitType(e).isAvailable())
}

let function updateDistanceNativeUnitsText(obj) {
  let descObj = obj.findObject("distanceNativeUnitsText")
  if (!checkObj(descObj))
    return
  let distance = options.DISTANCE.value
  let desc = ::g_measure_type.DISTANCE.getMeasureUnitsText(distance)
  descObj.setValue(desc)
}

let function updateArmorPiercingText(obj) {
  let descObj = obj.findObject("armorPiercingText")
  if (!checkObj(descObj))
    return
  local desc = loc("ui/mdash")

  let bullet   = options.BULLET.value
  let distance = options.DISTANCE.value

  if (bullet?.bulletParams?.armorPiercing)
  {
    local pMin
    local pMax

    for (local i = 0; i < bullet.bulletParams.armorPiercing.len(); i++)
    {
      let v = {
        armor = bullet.bulletParams.armorPiercing[i]?[0] ?? 0,
        dist  = bullet.bulletParams.armorPiercingDist[i],
      }
      if (!pMin)
        pMin = { armor = v.armor, dist = 0 }
      if (!pMax)
        pMax = pMin
      if (v.dist <= distance)
        pMin = v
      pMax = v
      if (v.dist >= distance)
        break
    }
    if (pMax && pMax.dist < distance)
      pMax.dist = distance

    if (pMin && pMax)
    {
      let armor = stdMath.lerp(pMin.dist, pMax.dist, pMin.armor, pMax.armor, distance)
      desc = stdMath.round(armor).tointeger() + " " + loc("measureUnits/mm")
    }
  }

  descObj.setValue(desc)
}

local isBulletAvailable = @() options?.BULLET.value != null

options.template <- {
  id = "" //used from type name
  sortId = 0
  labelLocId = null
  controlStyle = ""
  items  = []
  values = []
  value = null
  defValue = null
  valueWidth = null

  getLabel = @() this.labelLocId && loc(this.labelLocId)
  getControlMarkup = function() {
    return ::create_option_combobox(this.id, [], -1, "onChangeOption", true,
      { controlStyle = this.controlStyle })
  }
  getInfoRows = @() null

  onChange = function(handler, scene, obj) {
    this.value = this.getValFromObj(obj)
    this.afterChangeFunc?(obj)
    this.updateDependentOptions(handler, scene)
    options.setAnalysisParams()
  }

  isVisible = @() true
  getValFromObj = @(obj) checkObj(obj) ? this.values?[obj.getValue()] : null
  afterChangeFunc = null

  updateDependentOptions = function(handler, scene) {
    handler.guiScene.setUpdatesEnabled(false, false)
    for (local i = this.sortId + 1;; i++) {
      let option = options.getBySortId(i)
      if (option == options.UNKNOWN)
        break
      option.update(handler, scene)
    }
    handler.guiScene.setUpdatesEnabled(true, true)
  }

  updateParams = @(_handler, _scene) null

  updateView = function(handler, scene) {
    let idx = this.values.indexof(this.value) ?? -1
    let markup = ::create_option_combobox(null, this.items, idx, null, false)
    let obj = scene.findObject(this.id)
    if (checkObj(obj))
      obj.getScene().replaceContentFromText(obj, markup, markup.len(), handler)
  }

  update = function(handler, scene, needReset = true) {
    if (needReset)
      this.updateParams(handler, scene)
    this.updateView(handler, scene)
    this.afterChangeFunc?(scene.findObject(this.id))
  }
}

options.addTypes <- function(typesTable)
{
  enums.addTypes(this, typesTable, null, "id")
  this.types.sort(@(a, b) a.sortId <=> b.sortId)
}

local sortIdCount = 0
options.addTypes({
  UNKNOWN = {
    sortId = sortIdCount++
    isVisible = @() false
  }
  UNITTYPE = {
    sortId = sortIdCount++
    labelLocId = "mainmenu/threat"
    isVisible = @() getThreatEsUnitTypes().len() > 1

    updateParams = function(_handler, _scene)
    {
      let esUnitTypes = getThreatEsUnitTypes()
      let types = esUnitTypes.map(@(e) unitTypes.getByEsUnitType(e))
      this.values = esUnitTypes
      this.items  = ::u.map(types, @(t) { text = "{0} {1}".subst(t.fontIcon, t.getArmyLocName()) })
      let preferredEsUnitType = this.value ?? options.targetUnit.esUnitType
      this.value = this.values.indexof(preferredEsUnitType) != null ? preferredEsUnitType
        : (this.values?[0] ?? ES_UNIT_TYPE_INVALID)
    }
  }
  COUNTRY = {
    sortId = sortIdCount++
    controlStyle = "iconType:t='small';"
    getLabel = @() options.UNITTYPE.isVisible() ? null : loc("mainmenu/threat")

    updateParams = function(_handler, _scene)
    {
      let unitType = options.UNITTYPE.value
      this.values = ::u.filter(shopCountriesList, @(c) isCountryHaveUnitType(c, unitType))
      this.items  = ::u.map(this.values, @(c) { text = loc(c), image = ::get_country_icon(c) })
      let preferredCountry = this.value ?? options.targetUnit.shopCountry
      this.value = this.values.indexof(preferredCountry) != null ? preferredCountry
        : (this.values?[0] ?? "")
    }
  }
  RANK = {
    sortId = sortIdCount++

    updateParams = function(_handler, _scene) {
      let unitType = options.UNITTYPE.value
      let country = options.COUNTRY.value
      this.values = []
      for (local rank = 1; rank <= ::max_country_rank; rank++)
        if (hasUnitAtRank(rank, unitType, country, true, false))
          this.values.append(rank)
      this.items = ::u.map(this.values, @(r) {
        text = format(loc("conditions/unitRank/format"), ::get_roman_numeral(r))
      })
      let preferredRank = this.value ?? options.targetUnit.rank
      this.value = this.values?[::find_nearest(preferredRank, this.values)] ?? 0
    }
  }
  UNIT = {
    sortId = sortIdCount++

    updateParams = function(_handler, _scene) {
      let unitType = options.UNITTYPE.value
      let rank = options.RANK.value
      let country = options.COUNTRY.value
      let ediff = ::get_current_ediff()
      local list = ::get_units_list(@(u) u.esUnitType == unitType
        && u.shopCountry == country && u.rank == rank && u.isVisibleInShop())
      list = ::u.map(list, @(u) { unit = u, id = u.name, br = u.getBattleRating(ediff) })
      list.sort(@(a, b) a.br <=> b.br)
      this.values = ::u.map(list, @(v) v.unit)
      this.items = ::u.map(list, @(v) {
        text  = format("[%.1f] %s", v.br, ::getUnitName(v.id))
        image = ::image_for_air(v.unit)
        addDiv = UNIT.getMarkup(v.id, { showLocalState = false })
      })
      let targetUnitId = options.targetUnit.name
      let preferredUnitId = this.value?.name ?? targetUnitId
      this.value = this.values.findvalue(@(v) v.name == preferredUnitId) ??
        this.values.findvalue(@(v) v.name == targetUnitId) ??
        this.values?[0]

      if (this.value == null) // This combination of unitType/country/rank shouldn't be selectable
        ::script_net_assert_once("protection analysis units list empty", "Protection analysis: Units list empty")
    }
  }
  BULLET = {
    sortId = sortIdCount++
    labelLocId = "mainmenu/shell"
    visibleTypes = [ WEAPON_TYPE.GUNS, WEAPON_TYPE.ROCKETS, WEAPON_TYPE.AGM ]

    updateParams = function(_handler, _scene)
    {
      let unit = options.UNIT.value
      this.values = []
      this.items = []
      let bulletSetData = []
      let bulletNamesSet = []

      local curGunIdx = -1
      let groupsCount = getBulletsGroupCount(unit)

      for (local groupIndex = 0; groupIndex < getLastFakeBulletsIndex(unit); groupIndex++)
      {
        let gunIdx = getLinkedGunIdx(groupIndex, groupsCount, unit.unitType.bulletSetsQuantity, false)
        if (gunIdx == curGunIdx)
          continue

        let bulletsList = getBulletsList(unit.name, groupIndex, {
          needCheckUnitPurchase = false, needOnlyAvailable = false, needTexts = true
        })
        if (bulletsList.values.len())
          curGunIdx = gunIdx

        foreach(i, value in bulletsList.values)
        {
          let bulletsSet = getBulletsSetData(unit, value)
          let weaponBlkName = bulletsSet?.weaponBlkName
          let isBulletBelt = bulletsSet?.isBulletBelt ?? true

          if (!weaponBlkName)
            continue
          if (this.visibleTypes.indexof(bulletsSet?.weaponType) == null)
            continue

          let searchName = getBulletsSearchName(unit, value)
          let useDefaultBullet = searchName != value
          let bulletParameters = calculate_tank_bullet_parameters(unit.name,
            (useDefaultBullet && weaponBlkName) || getModificationBulletsEffect(searchName),
            useDefaultBullet, false)

          let bulletNames = isBulletBelt ? [] : (bulletsSet?.bulletNames ?? [])
          if (isBulletBelt)
            foreach(t, _data in bulletsSet.bulletDataByType)
              bulletNames.append(t)

          foreach (idx, bulletName in bulletNames)
          {
            local locName = bulletsList.items[i].text
            local bulletParams = bulletParameters[idx]
            local isDub = false
            if (isBulletBelt)
            {
              locName = " ".concat(format(loc("caliber/mm"), bulletsSet.caliber),
                loc($"{bulletName}/name/short"))
              let bulletType = bulletName
              bulletParams = bulletParameters.findvalue(@(p) p.bulletType == bulletType)
              // Find bullet dub by params
              isDub = bulletSetData.findvalue(@(p) p.bulletType == bulletType && p.mass == bulletParams.mass
                && p.speed == bulletParams.speed)
              if(!isDub)
                bulletSetData.append(bulletParams)
              // Need change name for the same bullet type but different params
              if(isInArray(locName, bulletNamesSet))
                locName = $"{locName}{bulletsList.items[i].text}"
            }
            else
              isDub = isInArray(locName, bulletNamesSet)

            if (isDub)
              continue

            local addDiv = ""

            if (isBulletBelt)
            {
              local bSet = bulletsSet.__merge({ bullets = [bulletName] })
              let bData = bulletsSet.bulletDataByType[bulletName]

              foreach(param in ["explosiveType", "explosiveMass", "bulletAnimations"])
              {
                bSet[param] <- bData?[param]
              }

              addDiv = SINGLE_BULLET.getMarkup(unit.name, bulletName, {
                modName = value,
                bSet,
                bulletParams })
            }
            else
              addDiv = MODIFICATION.getMarkup(unit.name, value, { hasPlayerInfo = false })

            bulletNamesSet.append(locName)
            this.values.append({
              bulletName = bulletName || ""
              weaponBlkName = weaponBlkName
              bulletParams = bulletParams
            })

            this.items.append({
              text = locName
              addDiv = addDiv
            })
          }
        }
      }

      // Collecting special shells
      let specialBulletTypes = [ "rocket" ]
      let unitBlk = unit ? ::get_full_unit_blk(unit.name) : null
      let weapons = getUnitWeapons(unitBlk)
      let knownWeapBlkArray = []

      foreach (weap in weapons)
      {
        if (!weap?.blk || weap?.dummy || isInArray(weap.blk, knownWeapBlkArray))
          continue
        knownWeapBlkArray.append(weap.blk)

        let { weaponBlk, weaponBlkPath } = getWeaponBlkParams(weap.blk, {})
        local bulletBlk = null

        foreach (t in specialBulletTypes)
          bulletBlk = bulletBlk ?? weaponBlk?[t]

        let locName = ::g_string.utf8ToUpper(
          loc("weapons/{0}".subst(getWeaponNameByBlkPath(weaponBlkPath))), 1)
        if (!bulletBlk || isInArray(locName, bulletNamesSet))
          continue

        bulletNamesSet.append(locName)
        this.values.append({
          bulletName = ""
          weaponBlkName = weaponBlkPath
          bulletParams = calculate_tank_bullet_parameters(unit.name, weaponBlkPath, true, false)?[0]
          sortVal = bulletBlk?.caliber ?? 0
        })

        this.items.append({
          text = locName
          addDiv = SINGLE_WEAPON.getMarkup(unit.name, {
            blkPath = weaponBlkPath
            tType = weap.trigger
            presetName = weap.presetId
          })
        })
      }

      this.value = this.values?[0]
    }

    afterChangeFunc = function(obj) {
      updateArmorPiercingText(options.nestObj)
      let parentObj = obj.getParent().getParent()
      if (!parentObj?.isValid())
        return

      parentObj.display = isBulletAvailable() ? "show" : "hide"
    }
  }
  DISTANCE = {
    sortId = sortIdCount++
    labelLocId = "distance"
    value = -1
    defValue = -1
    minValue = -1
    maxValue = -1
    step = 0
    valueWidth = "@dmInfoTextWidth"

    getControlMarkup = function() {
      return ::handyman.renderCached("%gui/dmViewer/distanceSlider.tpl", {
        containerId = "container_" + this.id
        id = this.id
        min = 0
        max = 0
        value = 0
        step = 0
        width = "fw"
        btnOnDec = "onButtonDec"
        btnOnInc = "onButtonInc"
        onChangeSliderValue = "onChangeOption"
      })
    }

    getInfoRows = function() {
      let res = [{
        valueId = "armorPiercingText"
        valueWidth = this.valueWidth
        label = loc("bullet_properties/armorPiercing") + loc("ui/colon")
      }]

      if (::g_measure_type.DISTANCE.isMetricSystem() == false)
        res.insert(0, {
        valueId = "distanceNativeUnitsText"
        valueWidth = "fw"
        label = ""
      })

      return res
    }

    getValFromObj = @(obj) checkObj(obj) ? obj.getValue() : 0

    afterChangeFunc = function(obj) {
      let parentObj = obj.getParent().getParent()
      parentObj.findObject("value_" + this.id).setValue(this.value + loc("measureUnits/meters_alt"))
      ::enableBtnTable(parentObj, {
        buttonInc = this.value < this.maxValue
        buttonDec = this.value > this.minValue
      })
      updateDistanceNativeUnitsText(options.nestObj)
      updateArmorPiercingText(options.nestObj)
    }

    updateParams = function(_handler, _scene) {
      this.minValue = 0
      this.maxValue = options.UNIT.value?.isShipOrBoat() ? 15000 : 5000
      this.step     = 100
      let preferredDistance = this.value >= 0 ? this.value
        : (options.UNIT.value?.isShipOrBoat() ? 2000 : 500)
      this.value = clamp(preferredDistance, this.minValue, this.maxValue)
    }

    updateView = function(_handler, scene) {
      let obj = scene.findObject(this.id)
      if (!obj?.isValid())
        return
      let parentObj = obj.getParent().getParent()
      if (isBulletAvailable()) {
        obj.max = this.maxValue
        obj.optionAlign = this.step
        obj.setValue(this.value)
      }
      parentObj.display = isBulletAvailable() ? "show" : "hide"
    }
  }
})

options.init <- function(handler, scene) {
  this.nestObj = scene
  let needReinit = !this.isSaved
    || !targetTypeToThreatTypes[this.targetUnit.esUnitType].contains(this.UNITTYPE.value)

  if (needReinit)
    this.types.each(@(o) o.value = o.defValue)

  this.types.each(@(o) o.update(handler, scene, needReinit))
  this.setAnalysisParams()
}

options.setAnalysisParams <- function() {
  let bullet   = options.BULLET.value
  let distance = options.DISTANCE.value
  ::set_protection_checker_params(bullet?.weaponBlkName ?? "", bullet?.bulletName ?? "", distance)
}

options.get <- @(id) this?[id] ?? this.UNKNOWN

options.getBySortId <- function(idx) {
  return enums.getCachedType("sortId", idx, this.cache.bySortId, this, this.UNKNOWN)
}

return options
