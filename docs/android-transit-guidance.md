# Android walking and public transport guidance

The next Android update should let the rider start the transit itinerary they selected. Keep that selection, including its ordered legs and Transitous trip and stop IDs, for the entire trip.

- Walk to the boarding stop with turn-by-turn walking guidance and the user's walking-router preference.
- At the boarding stop, show the line, direction, platform, and next departures. Provide a boarding confirmation when proximity and the timetable are ambiguous.
- On board, follow the chosen leg along its path and announce upcoming stops. Use the itinerary's stop order and timestamps alongside position fixes. Support missing GPS and distinguish a scheduled time from a live prediction.
- At a transfer, resume walking guidance to the next platform, then return to vehicle tracking for the next ride. After the final vehicle, guide the last walk to the destination.
- Keep the selected journey visible and allow the rider to recover from a missed connection or wrong vehicle.

The transit map and departure board share Transitous stop IDs. Transit legs retain their boarding stop, intermediate stops, alighting stop, and trip ID. Use these when building the guidance session.
