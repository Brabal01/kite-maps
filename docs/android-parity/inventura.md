# Inventura Kite Driving

Rozsahy jsou diffs mezi dvěma pevnými snapshoty. U Androidu je pod `android/` 119 změněných cest. Historický upstream `779daee` není použitý jako základ Android diffu.

## Android

`2620575a74edea00acf04deac867cd99d22060e5` → `097c9c62943ba00ac62f568a7a7258a5fbc499ab`

125 položek.

```text
R078	.github/fdroid/metadata/app.kite.yml	.github/fdroid/metadata/app.kite.driving.yml
M	.github/fdroid/publish.sh
M	.github/workflows/android.yml
M	README.md
M	android/app/build.gradle.kts
M	android/app/src/main/AndroidManifest.xml
A	android/app/src/main/assets/models/drive_alfa_147.glb
A	android/app/src/main/assets/models/drive_van.glb
A	android/app/src/main/assets/models/lamp.glb
A	android/app/src/main/assets/models/lamp_lens.glb
A	android/app/src/main/assets/offline-regions.json
M	android/app/src/main/kotlin/app/kite/AppModel.kt
A	android/app/src/main/kotlin/app/kite/Cruise.kt
M	android/app/src/main/kotlin/app/kite/DriveService.kt
A	android/app/src/main/kotlin/app/kite/ElevationProfile.kt
M	android/app/src/main/kotlin/app/kite/KiteApp.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
A	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapCam.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
A	android/app/src/main/kotlin/app/kite/MapPalette.kt
A	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
A	android/app/src/main/kotlin/app/kite/OfflineMaps.kt
A	android/app/src/main/kotlin/app/kite/OfflineRegions.kt
A	android/app/src/main/kotlin/app/kite/OpenMapStyle.kt
A	android/app/src/main/kotlin/app/kite/PhoneCompass.kt
A	android/app/src/main/kotlin/app/kite/QuickLaunch.kt
A	android/app/src/main/kotlin/app/kite/SatelliteStyle.kt
A	android/app/src/main/kotlin/app/kite/SavedPlans.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/Theme.kt
A	android/app/src/main/kotlin/app/kite/TransitGuidance.kt
A	android/app/src/main/kotlin/app/kite/TransitReminders.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
A	android/app/src/main/kotlin/app/kite/ui/CruiseView.kt
M	android/app/src/main/kotlin/app/kite/ui/Diagnostics.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
A	android/app/src/main/kotlin/app/kite/ui/ElevationProfile.kt
A	android/app/src/main/kotlin/app/kite/ui/GoogleReviewsPage.kt
A	android/app/src/main/kotlin/app/kite/ui/IndoorFloors.kt
A	android/app/src/main/kotlin/app/kite/ui/LayersSheet.kt
A	android/app/src/main/kotlin/app/kite/ui/MapboxAttribution.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
A	android/app/src/main/kotlin/app/kite/ui/NavigationPip.kt
A	android/app/src/main/kotlin/app/kite/ui/NearbyDepartures.kt
A	android/app/src/main/kotlin/app/kite/ui/OfflineMapsPage.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/Results.kt
A	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
A	android/app/src/main/kotlin/app/kite/ui/StopResults.kt
M	android/app/src/main/kotlin/app/kite/ui/StreetViewScreen.kt
A	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
A	android/app/src/main/kotlin/app/kite/ui/TransitTimeline.kt
A	android/app/src/main/res/drawable-nodpi/drive_alfa_147.webp
A	android/app/src/main/res/drawable-nodpi/drive_alfa_147_tilt.webp
A	android/app/src/main/res/drawable-nodpi/drive_van.webp
A	android/app/src/main/res/drawable-nodpi/drive_van_tilt.webp
A	android/app/src/main/res/drawable-nodpi/icon_night.webp
A	android/app/src/main/res/drawable-nodpi/icon_porcelain.webp
A	android/app/src/main/res/drawable-nodpi/icon_trail.webp
A	android/app/src/main/res/drawable-nodpi/mapbox_attribution.png
M	android/app/src/main/res/values/strings.xml
M	android/app/src/main/res/xml/shortcuts.xml
A	android/app/src/test/kotlin/app/kite/MapChromeTests.kt
A	android/app/src/test/kotlin/app/kite/NavCameraLayoutTests.kt
A	android/app/src/test/kotlin/app/kite/RoadStartTests.kt
A	android/app/src/test/kotlin/app/kite/SatelliteStyleTests.kt
A	android/core/src/main/kotlin/app/kite/core/Arrival.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
A	android/core/src/main/kotlin/app/kite/core/CleanAir.kt
A	android/core/src/main/kotlin/app/kite/core/CleanAirShapes.kt
A	android/core/src/main/kotlin/app/kite/core/Daylight.kt
A	android/core/src/main/kotlin/app/kite/core/FuelPrices.kt
M	android/core/src/main/kotlin/app/kite/core/Geo.kt
M	android/core/src/main/kotlin/app/kite/core/Google.kt
A	android/core/src/main/kotlin/app/kite/core/GooglePlaceMedia.kt
A	android/core/src/main/kotlin/app/kite/core/IndoorMaps.kt
A	android/core/src/main/kotlin/app/kite/core/KiteLinks.kt
M	android/core/src/main/kotlin/app/kite/core/MapLinks.kt
A	android/core/src/main/kotlin/app/kite/core/MapboxDirections.kt
M	android/core/src/main/kotlin/app/kite/core/Misc.kt
M	android/core/src/main/kotlin/app/kite/core/Model.kt
M	android/core/src/main/kotlin/app/kite/core/NavZoom.kt
A	android/core/src/main/kotlin/app/kite/core/NavigationStreetLabels.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
A	android/core/src/main/kotlin/app/kite/core/OpenPlaceSearch.kt
A	android/core/src/main/kotlin/app/kite/core/OutdoorData.kt
A	android/core/src/main/kotlin/app/kite/core/PidRealtime.kt
A	android/core/src/main/kotlin/app/kite/core/Reviews.kt
A	android/core/src/main/kotlin/app/kite/core/RoadAhead.kt
M	android/core/src/main/kotlin/app/kite/core/Roundabouts.kt
A	android/core/src/main/kotlin/app/kite/core/RouteTrafficPaint.kt
M	android/core/src/main/kotlin/app/kite/core/Search.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
A	android/core/src/main/kotlin/app/kite/core/TransitBoarding.kt
A	android/core/src/main/kotlin/app/kite/core/TransitRide.kt
A	android/core/src/main/kotlin/app/kite/core/TransitTiming.kt
M	android/core/src/main/kotlin/app/kite/core/TripNotes.kt
M	android/core/src/test/kotlin/app/kite/core/CameraTests.kt
A	android/core/src/test/kotlin/app/kite/core/DaylightTests.kt
A	android/core/src/test/kotlin/app/kite/core/FuelPricesTests.kt
A	android/core/src/test/kotlin/app/kite/core/GooglePlaceMediaTests.kt
A	android/core/src/test/kotlin/app/kite/core/IndoorMapsTests.kt
A	android/core/src/test/kotlin/app/kite/core/KiteLinksTests.kt
A	android/core/src/test/kotlin/app/kite/core/MapSearchTests.kt
A	android/core/src/test/kotlin/app/kite/core/MapboxDirectionsTests.kt
A	android/core/src/test/kotlin/app/kite/core/MatcherTests.kt
M	android/core/src/test/kotlin/app/kite/core/NavZoomTests.kt
A	android/core/src/test/kotlin/app/kite/core/NavigationContinuityTests.kt
A	android/core/src/test/kotlin/app/kite/core/OpenPlaceSearchTests.kt
A	android/core/src/test/kotlin/app/kite/core/OutdoorDataTests.kt
A	android/core/src/test/kotlin/app/kite/core/RouteAndTransitUpdateTests.kt
M	android/core/src/test/kotlin/app/kite/core/RoutingTests.kt
M	android/core/src/test/kotlin/app/kite/core/SmallTests.kt
A	android/core/src/test/kotlin/app/kite/core/TransitBoardingTests.kt
A	android/core/src/test/kotlin/app/kite/core/TransitRailGeometryTests.kt
A	android/core/src/test/kotlin/app/kite/core/TransitRideTests.kt
M	android/settings.gradle.kts
A	docs/android-transit-guidance.md
A	licenses/Mapbox-GL-JS.txt
```

## Nativní Swift, sestavení a distribuce

`52439d5dbeb984954e22c854e0efbe5c4aa061d5` → `80677d0f8fb37772b7bf0f9145d12da893ad4250`

51 položek.

```text
R078	.github/fdroid/metadata/app.kite.yml	.github/fdroid/metadata/app.kite.driving.yml
M	.github/fdroid/publish.sh
M	.github/workflows/android.yml
M	.github/workflows/build.yml
A	.github/workflows/kite-ios-native.yml
A	App/Assets.xcassets/DriveAlfa.imageset/Contents.json
A	App/Assets.xcassets/DriveAlfa.imageset/vehicle.png
A	App/Assets.xcassets/DriveAlfaTilt.imageset/Contents.json
A	App/Assets.xcassets/DriveAlfaTilt.imageset/vehicle.png
A	App/Assets.xcassets/DriveVan.imageset/Contents.json
A	App/Assets.xcassets/DriveVan.imageset/vehicle.png
A	App/Assets.xcassets/DriveVanTilt.imageset/Contents.json
A	App/Assets.xcassets/DriveVanTilt.imageset/vehicle.png
A	App/Resources/offline-regions.json
M	App/Sources/AppModel.swift
M	App/Sources/AppSettings.swift
M	App/Sources/ContentView.swift
M	App/Sources/DirectionsViews.swift
A	App/Sources/DriveMarker.swift
A	App/Sources/IndoorView.swift
M	App/Sources/KitePages.swift
M	App/Sources/MapIcons.swift
M	App/Sources/MapView.swift
M	App/Sources/NavGlide.swift
M	App/Sources/NavigationViews.swift
M	App/Sources/Navigator.swift
A	App/Sources/OfflineDownloads.swift
M	App/Sources/PanoramaViewer.swift
A	App/Sources/PidKeyStore.swift
M	App/Sources/PlaceViews.swift
A	App/Sources/PragueTransitSettings.swift
A	App/Sources/RouteAheadView.swift
A	App/Sources/RouteProfileView.swift
A	App/Sources/SavedRoutes.swift
M	App/Sources/SettingsViews.swift
M	App/Sources/StreetViews.swift
A	App/Sources/TransitJourney.swift
A	App/Sources/TransitJourneyViews.swift
A	App/Sources/TransitReminders.swift
A	VelaCore/Sources/VelaCore/IndoorMap.swift
M	VelaCore/Sources/VelaCore/OSRM.swift
A	VelaCore/Sources/VelaCore/OpenMapSearch.swift
A	VelaCore/Sources/VelaCore/PidRealtime.swift
A	VelaCore/Sources/VelaCore/RouteEngine.swift
A	VelaCore/Sources/VelaCore/RouteRoadEvent.swift
A	VelaCore/Sources/VelaCore/StationAccess.swift
M	VelaCore/Sources/VelaCore/Transit.swift
A	VelaCore/Sources/VelaCore/TransitTransfer.swift
M	VelaCore/Sources/VelaCore/Valhalla.swift
A	VelaCore/Tests/VelaCoreTests/RouteRoadEventTests.swift
M	project.yml
```

## Android commity v pořadí první rodičovské linie

### `8c1c06b` Add Mapbox maps and driving guidance to Kite Android

```text
R078	.github/fdroid/metadata/app.kite.yml	.github/fdroid/metadata/app.kite.driving.yml
M	.github/fdroid/publish.sh
M	.github/workflows/android.yml
M	README.md
M	android/app/build.gradle.kts
M	android/app/src/main/AndroidManifest.xml
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteApp.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Diagnostics.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
A	android/app/src/main/kotlin/app/kite/ui/MapboxAttribution.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
A	android/app/src/main/res/drawable-nodpi/mapbox_attribution.png
M	android/app/src/main/res/values/strings.xml
M	android/app/src/main/res/xml/shortcuts.xml
A	android/core/src/main/kotlin/app/kite/core/MapboxDirections.kt
M	android/core/src/main/kotlin/app/kite/core/Model.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
A	android/core/src/test/kotlin/app/kite/core/MapboxDirectionsTests.kt
A	licenses/Mapbox-GL-JS.txt
```

### `8747036` Document Mapbox terms and driving guidance

```text
M	README.md
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
```

### `089c946` Restore map gestures, turn previews and nearby places

```text
M	README.md
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/core/src/main/kotlin/app/kite/core/Search.kt
M	android/core/src/test/kotlin/app/kite/core/SmallTests.kt
```

### `0feb41f` Add Mapbox Standard scenery and Google place media

```text
M	README.md
M	android/app/build.gradle.kts
A	android/app/src/main/assets/models/lamp.glb
A	android/app/src/main/assets/models/lamp_lens.glb
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
A	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
A	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
A	android/app/src/main/kotlin/app/kite/ui/GoogleReviewsPage.kt
M	android/app/src/main/kotlin/app/kite/ui/MapboxAttribution.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/StreetViewScreen.kt
M	android/core/src/main/kotlin/app/kite/core/Google.kt
A	android/core/src/main/kotlin/app/kite/core/GooglePlaceMedia.kt
M	android/core/src/main/kotlin/app/kite/core/Misc.kt
M	android/core/src/main/kotlin/app/kite/core/Model.kt
A	android/core/src/test/kotlin/app/kite/core/GooglePlaceMediaTests.kt
M	android/settings.gradle.kts
```

### `1dfcda6` Customize the driving map and show stops and hazards ahead

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
A	android/app/src/main/kotlin/app/kite/MapPalette.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
A	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
M	android/core/src/test/kotlin/app/kite/core/CameraTests.kt
```

### `6460976` Add arrival parking, road reports and outdoor layers to Kite

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
A	android/app/src/main/kotlin/app/kite/ElevationProfile.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapPalette.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Actions.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
A	android/app/src/main/kotlin/app/kite/ui/ElevationProfile.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/core/src/main/kotlin/app/kite/core/MapboxDirections.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
A	android/core/src/main/kotlin/app/kite/core/OutdoorData.kt
M	android/core/src/main/kotlin/app/kite/core/Search.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
A	android/core/src/test/kotlin/app/kite/core/OutdoorDataTests.kt
A	docs/android-transit-guidance.md
```

### `0ca7f34` Reduce map stalls, restore OSM overlays and guide transit trips

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/DriveService.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
A	android/app/src/main/kotlin/app/kite/OpenMapStyle.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
A	android/app/src/main/kotlin/app/kite/TransitGuidance.kt
M	android/app/src/main/kotlin/app/kite/ui/Actions.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
A	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
M	android/core/src/main/kotlin/app/kite/core/Geo.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
M	android/core/src/main/kotlin/app/kite/core/OutdoorData.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
A	android/core/src/main/kotlin/app/kite/core/TransitRide.kt
A	android/core/src/test/kotlin/app/kite/core/TransitRideTests.kt
M	docs/android-transit-guidance.md
```

### `de2a871` Customize map controls and improve route planning and transit guidance

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
A	android/app/src/main/kotlin/app/kite/SavedPlans.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/Theme.kt
M	android/app/src/main/kotlin/app/kite/TransitGuidance.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
A	android/core/src/main/kotlin/app/kite/core/Daylight.kt
A	android/core/src/main/kotlin/app/kite/core/TransitBoarding.kt
A	android/core/src/test/kotlin/app/kite/core/DaylightTests.kt
A	android/core/src/test/kotlin/app/kite/core/TransitBoardingTests.kt
M	android/core/src/test/kotlin/app/kite/core/TransitRideTests.kt
```

### `26e3624` Restore navigation startup and refine search and map controls

```text
M	android/app/build.gradle.kts
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/Theme.kt
M	android/app/src/main/kotlin/app/kite/TransitGuidance.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
A	android/app/src/test/kotlin/app/kite/MapChromeTests.kt
A	android/app/src/test/kotlin/app/kite/RoadStartTests.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
M	android/core/src/main/kotlin/app/kite/core/Search.kt
A	android/core/src/test/kotlin/app/kite/core/MapSearchTests.kt
```

### `789976c` Integrate Kite 0.7.17 and improve OSM search and Mapbox rendering

```text
M	android/app/build.gradle.kts
M	android/app/src/main/kotlin/app/kite/AppModel.kt
A	android/app/src/main/kotlin/app/kite/Cruise.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapCam.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/OpenMapStyle.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/Theme.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
A	android/app/src/main/kotlin/app/kite/ui/CruiseView.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/Results.kt
A	android/core/src/main/kotlin/app/kite/core/Arrival.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
A	android/core/src/main/kotlin/app/kite/core/CleanAir.kt
A	android/core/src/main/kotlin/app/kite/core/CleanAirShapes.kt
M	android/core/src/main/kotlin/app/kite/core/Geo.kt
M	android/core/src/main/kotlin/app/kite/core/Google.kt
M	android/core/src/main/kotlin/app/kite/core/Misc.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
A	android/core/src/main/kotlin/app/kite/core/OpenPlaceSearch.kt
M	android/core/src/main/kotlin/app/kite/core/OutdoorData.kt
A	android/core/src/main/kotlin/app/kite/core/Reviews.kt
A	android/core/src/main/kotlin/app/kite/core/RoadAhead.kt
M	android/core/src/main/kotlin/app/kite/core/Search.kt
M	android/core/src/main/kotlin/app/kite/core/TripNotes.kt
M	android/core/src/test/kotlin/app/kite/core/CameraTests.kt
A	android/core/src/test/kotlin/app/kite/core/MatcherTests.kt
A	android/core/src/test/kotlin/app/kite/core/OpenPlaceSearchTests.kt
```

### `040bd63` Add driving vehicle markers and repair satellite and Road Ahead

```text
A	android/app/src/main/assets/models/drive_alfa_147.glb
A	android/app/src/main/assets/models/drive_van.glb
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
A	android/app/src/main/kotlin/app/kite/SatelliteStyle.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/Theme.kt
M	android/app/src/main/kotlin/app/kite/ui/CruiseView.kt
M	android/app/src/main/kotlin/app/kite/ui/MapboxAttribution.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/Results.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
A	android/app/src/main/res/drawable-nodpi/drive_alfa_147.webp
A	android/app/src/main/res/drawable-nodpi/drive_alfa_147_tilt.webp
A	android/app/src/main/res/drawable-nodpi/drive_van.webp
A	android/app/src/main/res/drawable-nodpi/drive_van_tilt.webp
A	android/app/src/test/kotlin/app/kite/SatelliteStyleTests.kt
```

### `37c57d5` Recenter both map renderers when road navigation starts

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
A	android/app/src/test/kotlin/app/kite/NavCameraLayoutTests.kt
```

### `22428fe` Rework transit and walking and preload navigation map data

```text
M	android/app/build.gradle.kts
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
M	android/core/src/main/kotlin/app/kite/core/Model.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
M	android/core/src/test/kotlin/app/kite/core/CameraTests.kt
M	android/core/src/test/kotlin/app/kite/core/MapboxDirectionsTests.kt
```

### `d7c7e1a` Smooth map transitions and add live transit and route surfaces

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapCam.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/ElevationProfile.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
M	android/core/src/main/kotlin/app/kite/core/Misc.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
M	android/core/src/test/kotlin/app/kite/core/OutdoorDataTests.kt
M	android/core/src/test/kotlin/app/kite/core/TransitRideTests.kt
```

### `7302d55` Give guidance camera priority and redesign map layers

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
A	android/app/src/main/kotlin/app/kite/ui/LayersSheet.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/test/kotlin/app/kite/NavCameraLayoutTests.kt
```

### `796eca1` Preserve map perspective and improve places, street view and route details

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MapCam.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/OpenMapStyle.kt
M	android/app/src/main/kotlin/app/kite/SatelliteStyle.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/GoogleReviewsPage.kt
M	android/app/src/main/kotlin/app/kite/ui/LayersSheet.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/app/src/main/kotlin/app/kite/ui/StreetViewScreen.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
M	android/app/src/test/kotlin/app/kite/RoadStartTests.kt
M	android/app/src/test/kotlin/app/kite/SatelliteStyleTests.kt
M	android/core/src/main/kotlin/app/kite/core/Cameras.kt
M	android/core/src/main/kotlin/app/kite/core/Google.kt
M	android/core/src/main/kotlin/app/kite/core/GooglePlaceMedia.kt
M	android/core/src/main/kotlin/app/kite/core/Misc.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
M	android/core/src/test/kotlin/app/kite/core/GooglePlaceMediaTests.kt
M	android/core/src/test/kotlin/app/kite/core/TransitRideTests.kt
```

### `f85cb2b` Polish navigation previews, Street View and transit

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/KiteMapSurface.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapCam.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/TransitGuidance.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/LayersSheet.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/StreetViewScreen.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
M	android/app/src/test/kotlin/app/kite/RoadStartTests.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
M	android/core/src/main/kotlin/app/kite/core/Roundabouts.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
M	android/core/src/main/kotlin/app/kite/core/TransitRide.kt
M	android/core/src/test/kotlin/app/kite/core/MapboxDirectionsTests.kt
M	android/core/src/test/kotlin/app/kite/core/RoutingTests.kt
M	android/core/src/test/kotlin/app/kite/core/TransitRideTests.kt
```

### `2c42d88` Redesign along-route stop result cards

```text
M	android/app/src/main/kotlin/app/kite/Theme.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/Results.kt
A	android/app/src/main/kotlin/app/kite/ui/StopResults.kt
```

### `acb40e6` Improve driving camera, stop details and route previews

```text
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/OpenMapStyle.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/ElevationProfile.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/app/src/main/kotlin/app/kite/ui/StopResults.kt
A	android/core/src/main/kotlin/app/kite/core/FuelPrices.kt
M	android/core/src/main/kotlin/app/kite/core/Google.kt
M	android/core/src/main/kotlin/app/kite/core/Model.kt
M	android/core/src/main/kotlin/app/kite/core/NavZoom.kt
A	android/core/src/test/kotlin/app/kite/core/FuelPricesTests.kt
M	android/core/src/test/kotlin/app/kite/core/NavZoomTests.kt
```

### `ace7ef4` Add navigation PiP, Android shortcuts and map pickers

```text
M	android/app/src/main/AndroidManifest.xml
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/OpenMapStyle.kt
A	android/app/src/main/kotlin/app/kite/QuickLaunch.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
A	android/app/src/main/kotlin/app/kite/ui/NavigationPip.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/StopResults.kt
M	android/app/src/main/res/values/strings.xml
A	android/core/src/main/kotlin/app/kite/core/KiteLinks.kt
M	android/core/src/main/kotlin/app/kite/core/MapLinks.kt
A	android/core/src/test/kotlin/app/kite/core/KiteLinksTests.kt
```

### `34fab69` Add offline maps, route profiles and transit station access

```text
M	android/app/build.gradle.kts
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/ElevationProfile.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
A	android/app/src/main/kotlin/app/kite/OfflineMaps.kt
A	android/app/src/main/kotlin/app/kite/PhoneCompass.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/ElevationProfile.kt
A	android/app/src/main/kotlin/app/kite/ui/IndoorFloors.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
A	android/app/src/main/kotlin/app/kite/ui/OfflineMapsPage.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
A	android/core/src/main/kotlin/app/kite/core/IndoorMaps.kt
M	android/core/src/main/kotlin/app/kite/core/MapboxDirections.kt
M	android/core/src/main/kotlin/app/kite/core/Misc.kt
M	android/core/src/main/kotlin/app/kite/core/Model.kt
M	android/core/src/main/kotlin/app/kite/core/OSRM.kt
A	android/core/src/test/kotlin/app/kite/core/IndoorMapsTests.kt
M	android/core/src/test/kotlin/app/kite/core/MapboxDirectionsTests.kt
```

### `ccfe8cf` Stabilize navigation and add Android live guidance

```text
M	android/app/build.gradle.kts
M	android/app/src/main/AndroidManifest.xml
A	android/app/src/main/assets/offline-regions.json
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/DriveService.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/Navigator.kt
M	android/app/src/main/kotlin/app/kite/OfflineMaps.kt
A	android/app/src/main/kotlin/app/kite/OfflineRegions.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/IndoorFloors.kt
M	android/app/src/main/kotlin/app/kite/ui/OfflineMapsPage.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
A	android/app/src/main/res/drawable-nodpi/icon_night.webp
A	android/app/src/main/res/drawable-nodpi/icon_porcelain.webp
A	android/app/src/main/res/drawable-nodpi/icon_trail.webp
M	android/core/src/main/kotlin/app/kite/core/IndoorMaps.kt
M	android/core/src/main/kotlin/app/kite/core/Misc.kt
A	android/core/src/main/kotlin/app/kite/core/NavigationStreetLabels.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
M	android/core/src/test/kotlin/app/kite/core/IndoorMapsTests.kt
A	android/core/src/test/kotlin/app/kite/core/NavigationContinuityTests.kt
```

### `3136045` Rework transit connections, indoor floors and offline downloads

```text
M	android/app/build.gradle.kts
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/MapCam.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/OfflineMaps.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/ui/Common.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/IndoorFloors.kt
M	android/app/src/main/kotlin/app/kite/ui/Navigation.kt
M	android/app/src/main/kotlin/app/kite/ui/OfflineMapsPage.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/PlaceViews.kt
M	android/app/src/main/kotlin/app/kite/ui/RoadAhead.kt
M	android/app/src/main/kotlin/app/kite/ui/StopResults.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
A	android/app/src/main/kotlin/app/kite/ui/TransitTimeline.kt
M	android/core/src/main/kotlin/app/kite/core/IndoorMaps.kt
A	android/core/src/main/kotlin/app/kite/core/PidRealtime.kt
A	android/core/src/main/kotlin/app/kite/core/RouteTrafficPaint.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
A	android/core/src/main/kotlin/app/kite/core/TransitTiming.kt
A	android/core/src/test/kotlin/app/kite/core/RouteAndTransitUpdateTests.kt
```

### `6e05a31` Restore close camera at navigation startup

```text
M	android/app/build.gradle.kts
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
```

### `1d05753` Keep navigation camera on GPS and improve saved transit trips

```text
M	android/app/build.gradle.kts
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/KiteMap.kt
M	android/app/src/main/kotlin/app/kite/MapIcons.kt
M	android/app/src/main/kotlin/app/kite/MapboxScenery.kt
M	android/app/src/main/kotlin/app/kite/NavGlide.kt
M	android/app/src/main/kotlin/app/kite/SavedPlans.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
M	android/app/src/main/kotlin/app/kite/ui/IndoorFloors.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitNavigation.kt
M	android/app/src/test/kotlin/app/kite/NavCameraLayoutTests.kt
M	android/core/src/main/kotlin/app/kite/core/IndoorMaps.kt
M	android/core/src/main/kotlin/app/kite/core/Transit.kt
A	android/core/src/test/kotlin/app/kite/core/TransitRailGeometryTests.kt
```

### `3501dea` Defer Mapbox HTTP setup until routing is requested

```text
M	android/core/src/main/kotlin/app/kite/core/MapboxDirections.kt
```

### `097c9c6` Add nearby departures, transit reminders and personal walking pace

```text
M	android/app/build.gradle.kts
M	android/app/src/main/AndroidManifest.xml
M	android/app/src/main/kotlin/app/kite/AppModel.kt
M	android/app/src/main/kotlin/app/kite/MainActivity.kt
M	android/app/src/main/kotlin/app/kite/SavedPlans.kt
M	android/app/src/main/kotlin/app/kite/Settings.kt
M	android/app/src/main/kotlin/app/kite/TransitGuidance.kt
A	android/app/src/main/kotlin/app/kite/TransitReminders.kt
M	android/app/src/main/kotlin/app/kite/ui/Browse.kt
M	android/app/src/main/kotlin/app/kite/ui/Directions.kt
A	android/app/src/main/kotlin/app/kite/ui/NearbyDepartures.kt
M	android/app/src/main/kotlin/app/kite/ui/Pages.kt
M	android/app/src/main/kotlin/app/kite/ui/TransitTimeline.kt
M	android/core/src/main/kotlin/app/kite/core/TransitTiming.kt
M	android/core/src/test/kotlin/app/kite/core/RouteAndTransitUpdateTests.kt
```
