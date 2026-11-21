package app.kite

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.kite.core.*

class TransitGuidance(val trip: TransitTrip, val destination: Place) {
    enum class Phase { WALK, BOARD, RIDE, COMPLETE }

    var legIndex by mutableIntStateOf(0)
        private set
    val leg: TransitLeg? get() = trip.legs.getOrNull(legIndex)
    var phase by mutableStateOf(Phase.WALK)
        private set
    var walking by mutableStateOf<Navigator?>(null)
    var walkingError by mutableStateOf(false)
    var boarding by mutableStateOf(false)
    var liveDeparture by mutableStateOf<Transitous.Departure?>(null)
    var overviewing by mutableStateOf(false)
    var following by mutableStateOf(true)
    var fix by mutableStateOf<Fix?>(null)
        private set
    var nextStop by mutableStateOf<TransitCall?>(null)
        private set
    var nearExit by mutableStateOf(false)
        private set
    var lastAlongAt by mutableStateOf<Long?>(null)
        private set
    private var tracker: TransitRide? = null
    private var departureMotion: TransitBoarding? = null
    private var toldExit = false
    private var closeFixes = 0
    private var boardedAt = 0L
    private var saidNext: TransitCall? = null

    fun prepareLeg() {
        nearExit = false
        nextStop = null
        lastAlongAt = null
        walkingError = false
        boarding = false
        liveDeparture = null
        saidNext = null
        following = true
        tracker = null
        toldExit = false
        closeFixes = 0
        phase = when (leg?.isWalk) {
            true -> Phase.WALK
            false -> Phase.BOARD
            null -> Phase.COMPLETE
        }
        departureMotion = leg?.takeIf { phase == Phase.BOARD }?.let { ride ->
            (ride.calls.firstOrNull()?.at ?: ride.path.firstOrNull())?.let { TransitBoarding(ride.path, it) }
        }
        fix?.let { shouldAutoBoard(it) }
        if (phase == Phase.BOARD) announce("Board ${leg?.line} at ${leg?.fromName} toward ${leg?.headsign ?: leg?.toName}.")
        if (phase == Phase.COMPLETE) announce("You have arrived at ${destination.name}.")
    }

    fun advance() {
        legIndex++
        prepareLeg()
    }

    fun board(ride: TransitRide) {
        if (phase != Phase.BOARD) return
        boarding = false
        tracker = ride
        boardedAt = System.currentTimeMillis()
        phase = Phase.RIDE
        nextStop = tracker?.next
        following = true
        sayNext(nextStop, scheduled = false)
    }

    fun observe(f: Fix): Boolean {
        fix = f
        val ride = tracker ?: return false
        val update = ride.observe(f.coord, f.accuracy, f.timeMillis)
        lastAlongAt = ride.lastPositionAt
        nextStop = ride.next
        nearExit = ride.nearExit
        if (update.exitApproach && !toldExit) {
            toldExit = true
            announce("Get off at the next stop, ${leg?.toName}.")
        } else if (update.nextChanged) sayNext(nextStop, scheduled = false)
        closeFixes = if (nearExit && f.accuracy in 0.0..75.0) closeFixes + 1 else 0
        return closeFixes >= 2 && (!f.speedKnown || f.speed < 4)
    }

    fun shouldAutoBoard(f: Fix): Boolean {
        if (phase != Phase.BOARD || boarding || f.ageMs !in 0..15_000) return false
        return departureMotion?.observe(f.coord, f.accuracy, f.speed, f.course, f.timeMillis, liveDeparture?.time ?: leg?.depart) == true
    }

    fun scheduledNext(time: Long) = tracker?.scheduledNext(time)

    fun tick(now: Long) {
        if (phase == Phase.RIDE && now - (lastAlongAt ?: boardedAt) > 25_000)
            sayNext(scheduledNext(now), scheduled = true)
    }

    private fun sayNext(call: TransitCall?, scheduled: Boolean) {
        if (call == null || call == saidNext) return
        saidNext = call
        announce(if (scheduled) "Scheduled next stop, ${call.name}." else "Next stop, ${call.name}.")
    }

    private fun announce(text: String) {
        if (AppSettings.voice && !AppSettings.voiceAlertsOnly && !Voice.onCall) Voice.say(text)
    }
}
