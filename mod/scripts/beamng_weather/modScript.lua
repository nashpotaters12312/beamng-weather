-- BeamNG Weather: Rain Overhaul
-- Runs when the mod is activated. It loads the main game-engine (GE) extension,
-- which loads the sub-modules (precipitation, wet roads, wet body, wet grip).
load("beamngWeather_rain")
setExtensionUnloadMode("beamngWeather_rain", "manual")
