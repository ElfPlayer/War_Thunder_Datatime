from "%scripts/dagui_library.nut" import *

//checked for explicitness
#no-root-fallback
#explicit-this

let { getCustomViewCountryData } = require("%scripts/worldWar/inOperation/wwOperationCustomAppearance.nut")

::gui_handlers.WwQueueDescriptionCustomHandler <- class extends ::gui_handlers.WwMapDescription
{
  function mapCountriesToView(side, _amountByCountry, joinedCountries)
  {
    let cuntriesByTeams = this.descItem.getCountriesByTeams()
    let countries = cuntriesByTeams?[side] ?? []
    let mapName = this.descItem.getId()
    return {
      countries = countries.map(function(countryId) {
        let customViewCountryData = getCustomViewCountryData(countryId, mapName)
        let customLocId = customViewCountryData.locId
        let countryNameText = countryId == customLocId
          ? loc(countryId)
          : "".concat(loc(customLocId), loc("ui/parentheses/space", {text = loc(countryId)}))
        return {
          countryNameText = countryNameText
          countryId       = countryId
          countryIcon     = customViewCountryData.icon
          isJoined        = isInArray(countryId, joinedCountries)
          side            = side
          isLeftAligned   = side == SIDE_1
        }
      })
    }
  }

  function updateCountriesList()
  {
    let obj = this.scene.findObject("div_before_text")
    if (!checkObj(obj))
      return

    let amountByCountry = this.descItem.getArmyGroupsAmountByCountries()
    let joinedCountries = this.descItem.getMyClanCountries()
    let sides = []
    foreach (side in ::g_world_war.getCommonSidesOrder())
      sides.append(this.mapCountriesToView(side, amountByCountry, joinedCountries))
    let view = {
      sides = sides
      vsText = loc("country/VS") + "\n "
    }

    let lastSelectedValue = ::get_obj_valid_index(obj.findObject("countries_container"))
    let data = ::handyman.renderCached("%gui/worldWar/wwOperationCountriesInfo.tpl", view)
    this.guiScene.replaceContentFromText(obj, data, data.len(), this)
    let isVisible = this.descItem.isMapActive()
    obj.show(isVisible)
    if (isVisible && lastSelectedValue >= 0)
      obj.findObject("countries_container").setValue(lastSelectedValue)
  }
}
