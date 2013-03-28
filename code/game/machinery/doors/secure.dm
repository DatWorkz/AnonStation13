#define AIRLOCK_WIRE_IDSCAN 1
#define AIRLOCK_WIRE_MAIN_POWER1 2
#define AIRLOCK_WIRE_MAIN_POWER2 3
#define AIRLOCK_WIRE_DOOR_BOLTS 4
#define AIRLOCK_WIRE_BACKUP_POWER1 5
#define AIRLOCK_WIRE_BACKUP_POWER2 6
#define AIRLOCK_WIRE_OPEN_DOOR 7
#define AIRLOCK_WIRE_AI_CONTROL 8
#define AIRLOCK_WIRE_ELECTRIFY 9
#define AIRLOCK_WIRE_CRUSH 10
#define AIRLOCK_WIRE_LIGHT 11
#define AIRLOCK_WIRE_HOLDOPEN 12
#define AIRLOCK_WIRE_FAKEBOLT1 13
#define AIRLOCK_WIRE_FAKEBOLT2 14
#define AIRLOCK_WIRE_ALERTAI 15
#define AIRLOCK_WIRE_DOOR_BOLTS_2 16
//#define AIRLOCK_WIRE_FINGERPRINT 17

/*
	New methods:
	pulse - sends a pulse into a wire for hacking purposes
	cut - cuts a wire and makes any necessary state changes
	mend - mends a wire and makes any necessary state changes
	isWireColorCut - returns 1 if that color wire is cut, or 0 if not
	isWireCut - returns 1 if that wire (e.g. AIRLOCK_WIRE_DOOR_BOLTS) is cut, or 0 if not
	canAIControl - 1 if the AI can control the airlock, 0 if not (then check canAIHack to see if it can hack in)
	canAIHack - 1 if the AI can hack into the airlock to recover control, 0 if not. Also returns 0 if the AI does not *need* to hack it.
	arePowerSystemsOn - 1 if the main or backup power are functioning, 0 if not. Does not check whether the power grid is charged or an APC has equipment on or anything like that. (Check (stat & NOPOWER) for that)
	requiresIDs - 1 if the airlock is requiring IDs, 0 if not
	isAllPowerCut - 1 if the main and backup power both have cut wires.
	regainMainPower - handles the effect of main power coming back on.
	loseMainPower - handles the effect of main power going offline. Usually (if one isn't already running) spawn a thread to count down how long it will be offline - counting down won't happen if main power was completely cut along with backup power, though, the thread will just sleep.
	loseBackupPower - handles the effect of backup power going offline.
	regainBackupPower - handles the effect of main power coming back on.
	shock - has a chance of electrocuting its target.
*/

//This generates the randomized airlock wire assignments for the game.
/proc/RandomAirlockWiresSecure()
	//to make this not randomize the wires, just set index to 1 and increment it in the flag for loop (after doing everything else).
	var/list/wires = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	airlockIndexToFlag = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	airlockIndexToWireColor = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	airlockWireColorToIndex = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	var/flagIndex = 1
	for (var/flag=1, flag<4096, flag+=flag)
		var/valid = 0
		while (!valid)
			var/colorIndex = rand(1, 12)
			if (wires[colorIndex] == 0)
				valid = 1
				wires[colorIndex] = flag
				airlockIndexToFlag[flagIndex] = flag
				airlockIndexToWireColor[flagIndex] = colorIndex
				airlockWireColorToIndex[colorIndex] = flagIndex
		flagIndex+=1
	return wires

/obj/machinery/door/secure
	name = "Secure Airlock"
	desc = "Good lord, at least they left out the overcomplicated death traps.  Looks to be a layer of armor plate you might be able to remove with a wrench."
	icon = 'Doorhatchele.dmi'
	icon_state = "door_closed"
	power_channel = ENVIRON

	var/aiControlDisabled = 0 //If 1, AI control is disabled until the AI hacks back in and disables the lock. If 2, the AI has bypassed the lock. If -1, the control is enabled but the AI had bypassed it earlier, so if it is disabled again the AI would have no trouble getting back in.
	var/hackProof = 0 // if 1, this door can't be hacked by the AI
	var/synDoorHacked = 0 // Has it been hacked? bool 1 = yes / 0 = no
	var/synHacking = 0 // Is hack in process y/n?
	var/secondsMainPowerLost = 0 //The number of seconds until power is restored.
	var/secondsBackupPowerLost = 0 //The number of seconds until power is restored.
	var/spawnPowerRestoreRunning = 0
	var/welded = null
	var/locked = 0
	var/list/air_locked
	var/wires = 65535
	secondsElectrified = 0 //How many seconds remain until the door is no longer electrified. -1 if it is permanently electrified until someone fixes it.
	var/aiDisabledIdScanner = 0
	var/aiHacking = 0
	var/obj/machinery/door/airlock/closeOther = null
	var/closeOtherId = null
	var/list/signalers = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	var/lockdownbyai = 0
	autoclose = 1
	var/doortype = 34
	var/justzap = 0
	var/safetylight = 1
	var/obj/item/weapon/airlock_electronics/electronics = null
	var/alert_probability = 20
	var/list/wire_index = list(
				"Orange" = 1,
				"Dark red" = 2,
				"White" = 3,
				"Yellow" = 4,
				"Red" = 5,
				"Blue" = 6,
				"Green" = 7,
				"Grey" = 8,
				"Black" = 9,
				"Pink" = 10,
				"Brown" = 11,
				"Maroon" = 12,
				"Aqua" = 13,
				"Turgoise" = 14,
				"Purple" = 15,
				"Rainbow" = 16,
				"Atomic Tangerine" = 17,
				"Neon Green" = 18,
				"Cotton Candy" = 19,
				"Plum" = 20,
				"Shamrock" = 21,
				"Indigo" = 22
			)
	var/wirenum = 16
	var/holdopen = 0
	var
		list/WireColorToFlag = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		list/IndexToFlag = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		list/IndexToWireColor = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		list/WireColorToIndex = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		is_detached = 0
	var/removal_step = 0
	var/hasShocked = 0

/obj/machinery/door/secure/New()
	..()
	//to make this not randomize the wires, just set index to 1 and increment it in the flag for loop (after doing everything else).
	var/flagIndex = 1
	for (var/flag=1, flag<65536, flag+=flag)
		var/valid = 0
		while (!valid)
			var/colorIndex = rand(1, 16)
			if (WireColorToFlag[colorIndex] == 0)
				valid = 1
				WireColorToFlag[colorIndex] = flag
				IndexToFlag[flagIndex] = flag
				IndexToWireColor[flagIndex] = colorIndex
				WireColorToIndex[colorIndex] = flagIndex
		flagIndex+=1
	return

/obj/machinery/door/secure/attackby(C as obj, mob/living/user as mob)
	//world << text("airlock attackby src [] obj [] mob []", src, C, user)
	if(istype(C, /obj/item/device/detective_scanner))
		return
	if(istype(C, /obj/item/weapon/screwdriver))
		src.p_open = !( src.p_open )
		src.update_icon()
	if(istype(C, /obj/item/weapon/wirecutters))
		return src.attack_hand(user)
	if(istype(C, /obj/item/weapon/crowbar) || istype(C, /obj/item/weapon/twohanded/fireaxe) )
		var/beingcrowbarred = null
		if(istype(C, /obj/item/weapon/crowbar) )
			beingcrowbarred = 1 //derp, Agouri
		else
			beingcrowbarred = 0
		if( beingcrowbarred && (density && welded && !operating && src.p_open && (!src.arePowerSystemsOn() || stat & NOPOWER) && !src.locked) )
			playsound(src.loc, 'sound/items/Crowbar.ogg', 100, 1)
			user.visible_message("[user] removes the electronics from the airlock assembly.", "You start to remove electronics from the airlock assembly.")
			if(do_after(user,40))
				user << "\blue You removed the airlock electronics!"
				switch(src.doortype)
					if(33) new/obj/structure/door_assembly/door_assembly_0( src.loc )

				var/obj/item/weapon/airlock_electronics/ae
				if(!electronics)
					ae = new/obj/item/weapon/airlock_electronics( src.loc )
					ae.conf_access = src.req_access
				else
					ae = electronics
					electronics = null
					ae.loc = src.loc

				del(src)
				return
		else if(arePowerSystemsOn() && !(stat & NOPOWER))
			user << "\blue The airlock's motors resist your efforts to force it."
		else if(locked)
			user << "\blue The airlock's bolts prevent it from being forced."
		else if( !welded && !operating )
			if(density)
				if(beingcrowbarred == 0) //being fireaxe'd
					var/obj/item/weapon/twohanded/fireaxe/F = C
					if(F:wielded)
						spawn(0)	open(1)
					else
						user << "\red You need to be wielding the Fire axe to do that."
				else
					spawn(0)	open(1)
			else
				if(beingcrowbarred == 0)
					var/obj/item/weapon/twohanded/fireaxe/F = C
					if(F:wielded)
						spawn(0)	close(1)
					else
						user << "\red You need to be wielding the Fire axe to do that."
				else
					spawn(0)	close(1)

	if(istype(C, /obj/item/device/multitool))
		return src.attack_hand(user)
	if(!issilicon(usr))
		if(src.isElectrified())
			if(!src.justzap)
				if(src.shock(user, 100))
					src.justzap = 1
					spawn (10)
						src.justzap = 0
					return
			else /*if(src.justzap)*/
				return
		if(ismob(C))
			return ..(C, user)
		src.add_fingerprint(user)
		switch(removal_step)
			if(0)
				if ((istype(C, /obj/item/weapon/weldingtool) && !( src.operating ) && src.density))
					var/obj/item/weapon/weldingtool/W = C
					if(W.remove_fuel(0,user))
						if (!src.welded)
							src.welded = 1
						else
							src.welded = null
						src.update_icon()
					return
				else if (istype(C, /obj/item/weapon/wrench))
					user << "You start to remove the bolts..."
					if(do_after(user,30))
						user << "Bolts removed"
						src.removal_step = 1
			if(1)
				if ((istype(C, /obj/item/weapon/weldingtool) && !( src.operating ) && src.density))
					var/obj/item/weapon/weldingtool/W = C
					if(W.remove_fuel(0,user))
						user << "You start to slice the armor..."
						if(do_after(user,20))
							user << "Armor sliced open"
							src.removal_step = 2
					return
				else if (istype(C, /obj/item/weapon/wrench))
					user << "You start wrench down the bolts..."
					if(do_after(user,30))
						user << "Bolts secured."
						src.removal_step = 0
			if(2)
				if ((istype(C, /obj/item/weapon/weldingtool) && !( src.operating ) && src.density))
					var/obj/item/weapon/weldingtool/W = C
					if(W.remove_fuel(0,user))
						user << "You start to fuse together the armor..."
						if(do_after(user,20))
							user << "Armor repaired"
							src.removal_step = 1
					return
				else if (istype(C, /obj/item/weapon/wrench))
					user << "You start to unfasten the armor from the circuits..."
					if(do_after(user,40))
						user << "Circuits exposed."
						src.removal_step = 3
						src.is_detached = 1
	else
		if (istype(C, /obj/item/weapon/wrench))
			user << "You start to fix the armor plate..."
			if(do_after(user,40))
				user << "Armor plates are back in position."
				src.is_detached = 0
				src.removal_step = 2


		else
			return ..(C, user)

/obj/machinery/door/secure/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if (src.isElectrified())
		if (istype(mover, /obj/item))
			var/obj/item/i = mover
			if (i.m_amt)
				var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
				s.set_up(5, 1, src)
				s.start()
	return ..()

obj/machinery/door/secure/Topic(href, href_list, var/nowindow = 0)
	if(!nowindow)
		..()
	if(usr.stat || usr.restrained())
		return
	add_fingerprint(usr)
	if(href_list["close"])
		usr << browse(null, "window=airlock")
		if(usr.machine==src)
			usr.machine = null
			return

	if((in_range(src, usr) && istype(src.loc, /turf)) && src.p_open)
		usr.machine = src
		if(href_list["wires"])
			var/t1 = text2num(href_list["wires"])
			if(!( istype(usr.get_active_hand(), /obj/item/weapon/wirecutters) ))
				usr << "You need wirecutters!"
				return
			if(src.isWireColorCut(t1))
				src.mend(t1)
			else
				src.cut(t1)
		else if(href_list["pulse"])
			var/t1 = text2num(href_list["pulse"])
			if(!istype(usr.get_active_hand(), /obj/item/device/multitool))
				usr << "You need a multitool!"
				return
			if(src.isWireColorCut(t1))
				usr << "You can't pulse a cut wire."
				return
			else
				src.pulse(t1)
		else if(href_list["signaler"])
			var/wirenum = text2num(href_list["signaler"])
			if(!istype(usr.get_active_hand(), /obj/item/device/assembly/signaler))
				usr << "You need a signaller!"
				return
			if(src.isWireColorCut(wirenum))
				usr << "You can't attach a signaller to a cut wire."
				return
			var/obj/item/device/assembly/signaler/R = usr.get_active_hand()
			if(R.secured)
				usr << "This radio can't be attached!"
				return
			var/mob/M = usr
			M.drop_item()
			R.loc = src
			R.airlock_wire = wirenum
			src.signalers[wirenum] = R
		else if(href_list["remove-signaler"])
			var/wirenum = text2num(href_list["remove-signaler"])
			if(!(src.signalers[wirenum]))
				usr << "There's no signaller attached to that wire!"
				return
			var/obj/item/device/assembly/signaler/R = src.signalers[wirenum]
			R.loc = usr.loc
			R.airlock_wire = null
			src.signalers[wirenum] = null


	if(istype(usr, /mob/living/silicon) && src.canAIControl())
		//AI
		//aiDisable - 1 idscan, 2 disrupt main power, 3 disrupt backup power, 4 drop door bolts, 5 un-electrify door, 7 close door, 8 door safties, 9 door speed
		//aiEnable - 1 idscan, 4 raise door bolts, 5 electrify door for 30 seconds, 6 electrify door indefinitely, 7 open door,  8 door safties, 9 door speed
		if(href_list["aiDisable"])
			var/code = text2num(href_list["aiDisable"])
			switch (code)
				if(1)
					//disable idscan
					if(src.isWireCut(AIRLOCK_WIRE_IDSCAN))
						usr << "The IdScan wire has been cut - So, you can't disable it, but it is already disabled anyways."
					else if(src.aiDisabledIdScanner)
						usr << "You've already disabled the IdScan feature."
					else
						src.aiDisabledIdScanner = 1
				if(2)
					//disrupt main power
					if(src.secondsMainPowerLost == 0)
						src.loseMainPower()
					else
						usr << "Main power is already offline."
				if(3)
					//disrupt backup power
					if(src.secondsBackupPowerLost == 0)
						src.loseBackupPower()
					else
						usr << "Backup power is already offline."
				if(4)
					//drop door bolts
					if(src.isWireCut(AIRLOCK_WIRE_DOOR_BOLTS))
						usr << "You can't drop the door bolts - The door bolt dropping wire has been cut."
					else if(src.locked!=1)
						src.locked = 1
						update_icon()
				if(5)
					//un-electrify door
					if(src.isWireCut(AIRLOCK_WIRE_ELECTRIFY))
						usr << text("Can't un-electrify the airlock - The electrification wire is cut.")
					else if(src.secondsElectrified==-1)
						src.secondsElectrified = 0
					else if(src.secondsElectrified>0)
						src.secondsElectrified = 0

				if(8)
					// Safeties!  We don't need no stinking safeties!
					if (src.isWireCut(AIRLOCK_WIRE_SAFETY))
						usr << text("Control to door sensors is disabled.")
					else
						usr << text("Firmware reports safeties already overriden.")



				if(9)
					// Door speed control
					if(src.isWireCut(AIRLOCK_WIRE_SPEED))
						usr << text("Control to door timing circuitry has been severed.")
					else if (src.normalspeed)
						normalspeed = 0
					else
						usr << text("Door timing circurity already accellerated.")

				if(7)
					//close door
					if(src.welded)
						usr << text("The airlock has been welded shut!")
					else if(src.locked)
						usr << text("The door bolts are down!")
					else if(!src.density)
						close()
					else
						open()

				if(10)
					// Bolt lights
					if(src.isWireCut(AIRLOCK_WIRE_LIGHT))
						usr << text("Control to door bolt lights has been severed.</a>")
					else
						usr << text("Door bolt lights are already disabled!")



		else if(href_list["aiEnable"])
			var/code = text2num(href_list["aiEnable"])
			switch (code)
				if(1)
					//enable idscan
					if(src.isWireCut(AIRLOCK_WIRE_IDSCAN))
						usr << "You can't enable IdScan - The IdScan wire has been cut."
					else if(src.aiDisabledIdScanner)
						src.aiDisabledIdScanner = 0
					else
						usr << "The IdScan feature is not disabled."
				if(4)
					//raise door bolts
					if(src.isWireCut(AIRLOCK_WIRE_DOOR_BOLTS))
						usr << text("The door bolt drop wire is cut - you can't raise the door bolts.<br>\n")
					else if(!src.locked)
						usr << text("The door bolts are already up.<br>\n")
					else
						if(src.arePowerSystemsOn())
							src.locked = 0
							update_icon()
						else
							usr << text("Cannot raise door bolts due to power failure.<br>\n")

				if(5)
					//electrify door for 30 seconds
					if(src.isWireCut(AIRLOCK_WIRE_ELECTRIFY))
						usr << text("The electrification wire has been cut.<br>\n")
					else if(src.secondsElectrified==-1)
						usr << text("The door is already indefinitely electrified. You'd have to un-electrify it before you can re-electrify it with a non-forever duration.<br>\n")
					else if(src.secondsElectrified!=0)
						usr << text("The door is already electrified. You can't re-electrify it while it's already electrified.<br>\n")
					else
						usr.attack_log += text("\[[time_stamp()]\] <font color='red'>Electrified the [name] at [x] [y] [z]</font>")
						src.secondsElectrified = 30
						spawn(10)
							while (src.secondsElectrified>0)
								src.secondsElectrified-=1
								if(src.secondsElectrified<0)
									src.secondsElectrified = 0
								src.updateUsrDialog()
								sleep(10)
				if(6)
					//electrify door indefinitely
					if(src.isWireCut(AIRLOCK_WIRE_ELECTRIFY))
						usr << text("The electrification wire has been cut.<br>\n")
					else if(src.secondsElectrified==-1)
						usr << text("The door is already indefinitely electrified.<br>\n")
					else if(src.secondsElectrified!=0)
						usr << text("The door is already electrified. You can't re-electrify it while it's already electrified.<br>\n")
					else
						usr.attack_log += text("\[[time_stamp()]\] <font color='red'>Electrified the [name] at [x] [y] [z]</font>")
						src.secondsElectrified = -1

				if (8) // Not in order >.>
					// Safeties!  Maybe we do need some stinking safeties!
					if (src.isWireCut(AIRLOCK_WIRE_SAFETY))
						usr << text("Control to door sensors is disabled.")
					else
						usr << text("Firmware reports safeties already in place.")

				if(9)
					// Door speed control
					if(src.isWireCut(AIRLOCK_WIRE_SPEED))
						usr << text("Control to door timing circuitry has been severed.")
					else if (!src.normalspeed)
						normalspeed = 1
						src.updateUsrDialog()
					else
						usr << text("Door timing circurity currently operating normally.")

				if(7)
					//open door
					if(src.welded)
						usr << text("The airlock has been welded shut!")
					else if(src.locked)
						usr << text("The door bolts are down!")
					else if(src.density)
						open()
					else
						close()

				if(10)
					// Bolt lights
					if(src.isWireCut(AIRLOCK_WIRE_LIGHT))
						usr << text("Control to door bolt lights has been severed.</a>")
					else
						usr << text("Door bolt lights are already enabled!")

	add_fingerprint(usr)
	update_icon()
	if(!nowindow)
		updateUsrDialog()
	return

/obj/machinery/door/secure/attack_hand(mob/user as mob)
	if(!istype(usr, /mob/living/silicon))
		if(src.isElectrified())
			if(src.shock(user, 100))
				return

	if(ishuman(user) && prob(40) && src.density)
		var/mob/living/carbon/human/H = user
		if(H.getBrainLoss() >= 60)
			playsound(src.loc, 'sound/effects/bang.ogg', 25, 1)
			if(!istype(H.head, /obj/item/clothing/head/helmet))
				for(var/mob/M in viewers(src, null))
					M << "\red [user] headbutts the airlock."
				var/datum/organ/external/affecting = H.get_organ("head")
				affecting.take_damage(10, 0)
				H.Stun(8)
				H.Weaken(5)
				H.UpdateDamageIcon()
			else
				for(var/mob/M in viewers(src, null))
					M << "\red [user] headbutts the airlock. Good thing they're wearing a helmet."
			return

	if(src.p_open)
		user.machine = src
		var/t1 = text("<B>Access Panel</B><br>\n")

		//t1 += text("[]: ", airlockFeatureNames[airlockWireColorToIndex[9]])
		t1 += getAirlockWires()

		t1 += text("<br>\n[]<br>\n[]<br>\n[]<br>\n[]", (src.locked ? "The door bolts have fallen!" : "The door bolts look up."), ((src.arePowerSystemsOn() && !(stat & NOPOWER)) ? "The test light is on." : "The test light is off!"), (src.aiControlDisabled==0 ? "The 'AI control allowed' light is on." : "The 'AI control allowed' light is off."), (src.secondsElectrified!=0 ? "The safety light is flashing!" : "The safety light is on."))

		t1 += text("<p><a href='?src=\ref[];close=1'>Close</a></p>\n", src)

		user << browse(t1, "window=airlock")
		onclose(user, "airlock")

	else
		..(user)
	return


/obj/machinery/door/secure/update_icon()
	if(overlays) overlays = null
	if(density)
		if(locked && safetylight && !air_locked)
			icon_state = "door_locked"
		else
			icon_state = "door_closed"
		if(p_open || welded || air_locked)
			overlays = list()
			if(p_open)
				overlays += image(icon, "panel_open")
			if(welded)
				overlays += image(icon, "welded")
			if(air_locked)
				overlays += image('Door1.dmi', "air")
	else
		icon_state = "door_open"

	return

/obj/machinery/door/secure/animate(animation)
	switch(animation)
		if("opening")
			if(overlays) overlays = null
			if(p_open)
				icon_state = "o_door_opening" //can not use flick due to BYOND bug updating overlays right before flicking
			else
				flick("door_opening", src)
		if("closing")
			if(overlays) overlays = null
			if(p_open)
				flick("o_door_closing", src)
			else
				flick("door_closing", src)
		if("spark")
			flick("door_spark", src)
		if("deny")
			flick("door_deny", src)
	return

/obj/machinery/door/secure/proc/isAllPowerCut()
	var/retval=0
	if(src.isWireCut(AIRLOCK_WIRE_MAIN_POWER1) || src.isWireCut(AIRLOCK_WIRE_MAIN_POWER2))
		if(src.isWireCut(AIRLOCK_WIRE_BACKUP_POWER1) || src.isWireCut(AIRLOCK_WIRE_BACKUP_POWER2))
			retval=1
	return retval

/obj/machinery/door/secure/proc/regainMainPower()
	if(src.secondsMainPowerLost > 0)
		src.secondsMainPowerLost = 0

/obj/machinery/door/secure/proc/loseMainPower()
	if(src.secondsMainPowerLost <= 0)
		src.secondsMainPowerLost = 60
		if(src.secondsBackupPowerLost < 10)
			src.secondsBackupPowerLost = 10
	if(!src.spawnPowerRestoreRunning)
		src.spawnPowerRestoreRunning = 1
		spawn(0)
			var/cont = 1
			while (cont)
				sleep(10)
				cont = 0
				if(src.secondsMainPowerLost>0)
					if((!src.isWireCut(AIRLOCK_WIRE_MAIN_POWER1)) && (!src.isWireCut(AIRLOCK_WIRE_MAIN_POWER2)))
						src.secondsMainPowerLost -= 1
						src.updateDialog()
					cont = 1

				if(src.secondsBackupPowerLost>0)
					if((!src.isWireCut(AIRLOCK_WIRE_BACKUP_POWER1)) && (!src.isWireCut(AIRLOCK_WIRE_BACKUP_POWER2)))
						src.secondsBackupPowerLost -= 1
						src.updateDialog()
					cont = 1
			src.spawnPowerRestoreRunning = 0
			src.updateDialog()

/obj/machinery/door/secure/proc/loseBackupPower()
	if(src.secondsBackupPowerLost < 60)
		src.secondsBackupPowerLost = 60

/obj/machinery/door/secure/proc/regainBackupPower()
	if(src.secondsBackupPowerLost > 0)
		src.secondsBackupPowerLost = 0

// shock user with probability prb (if all connections & power are working)
// returns 1 if shocked, 0 otherwise
// The preceding comment was borrowed from the grille's shock script
/obj/machinery/door/secure/proc/shock(mob/user, prb)
	if((stat & (NOPOWER)) || !src.arePowerSystemsOn())		// unpowered, no shock
		return 0
	if(hasShocked)
		return 0	//Already shocked someone recently?
	if(!prob(prb))
		return 0 //you lucked out, no shock for you
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(5, 1, src)
	s.start() //sparks always.
	if(electrocute_mob(user, get_area(src), src))
		hasShocked = 1
		sleep(10)
		hasShocked = 0
		return 1
	else
		return 0

/obj/machinery/door/secure/proc/cut(var/wireColor)
	var/wireFlag = airlockWireColorToFlag[wireColor]
	var/wireIndex = airlockWireColorToIndex[wireColor]
	wires &= ~wireFlag
	switch(wireIndex)
		if(AIRLOCK_WIRE_MAIN_POWER1 || AIRLOCK_WIRE_MAIN_POWER2)
			//Cutting either one disables the main door power, but unless backup power is also cut, the backup power re-powers the door in 10 seconds. While unpowered, the door may be crowbarred open, but bolts-raising will not work. Cutting these wires may electocute the user.
			src.loseMainPower()
			src.shock(usr, 50)
			src.updateUsrDialog()
		if(AIRLOCK_WIRE_DOOR_BOLTS)
			//Cutting this wire also drops the door bolts, and mending it does not raise them. (This is what happens now, except there are a lot more wires going to door bolts at present)
			if(src.locked!=1)
				src.locked = 1
			update_icon()
			src.updateUsrDialog()
		if(AIRLOCK_WIRE_BACKUP_POWER1 || AIRLOCK_WIRE_BACKUP_POWER2)
			//Cutting either one disables the backup door power (allowing it to be crowbarred open, but disabling bolts-raising), but may electocute the user.
			src.loseBackupPower()
			src.shock(usr, 50)
			src.updateUsrDialog()
		if(AIRLOCK_WIRE_AI_CONTROL)
			//one wire for AI control. Cutting this prevents the AI from controlling the door unless it has hacked the door through the power connection (which takes about a minute). If both main and backup power are cut, as well as this wire, then the AI cannot operate or hack the door at all.
			//aiControlDisabled: If 1, AI control is disabled until the AI hacks back in and disables the lock. If 2, the AI has bypassed the lock. If -1, the control is enabled but the AI had bypassed it earlier, so if it is disabled again the AI would have no trouble getting back in.
			if(src.aiControlDisabled == 0)
				src.aiControlDisabled = 1
			else if(src.aiControlDisabled == -1)
				src.aiControlDisabled = 2
			src.updateUsrDialog()
		if(AIRLOCK_WIRE_ELECTRIFY)
			//Cutting this wire electrifies the door, so that the next person to touch the door without insulated gloves gets electrocuted.
			if(src.secondsElectrified != -1)
				usr.attack_log += text("\[[time_stamp()]\] <font color='red'>Electrified the [name] at [x] [y] [z]</font>")
				src.secondsElectrified = -1
		if(AIRLOCK_WIRE_SPEED)
			autoclose = 0
			src.updateUsrDialog()


/obj/machinery/door/secure/proc/pulse(var/wireColor)
	//var/wireFlag = airlockWireColorToFlag[wireColor] //not used in this function
	var/wireIndex = airlockWireColorToIndex[wireColor]
	switch(wireIndex)
		if(AIRLOCK_WIRE_IDSCAN)
			//Sending a pulse through this flashes the red light on the door (if the door has power).
			if((src.arePowerSystemsOn()) && (!(stat & NOPOWER)))
				animate("deny")
		if(AIRLOCK_WIRE_MAIN_POWER1, AIRLOCK_WIRE_MAIN_POWER2)
			//Sending a pulse through either one causes a breaker to trip, disabling the door for 10 seconds if backup power is connected, or 1 minute if not (or until backup power comes back on, whichever is shorter).
			src.loseMainPower()
		if(AIRLOCK_WIRE_DOOR_BOLTS)
			//one wire for door bolts. Sending a pulse through this drops door bolts if they're not down (whether power's on or not),
			//raises them if they are down (only if power's on)
			if(!src.locked)
				src.locked = 1
				usr << "You hear a click from the bottom of the door."
				src.updateUsrDialog()
			else
				if(src.arePowerSystemsOn()) //only can raise bolts if power's on
					src.locked = 0
					usr << "You hear a click from inside the door."
					src.updateUsrDialog()
			update_icon()

		if(AIRLOCK_WIRE_BACKUP_POWER1, AIRLOCK_WIRE_BACKUP_POWER2)
			//two wires for backup power. Sending a pulse through either one causes a breaker to trip, but this does not disable it unless main power is down too (in which case it is disabled for 1 minute or however long it takes main power to come back, whichever is shorter).
			src.loseBackupPower()
		if(AIRLOCK_WIRE_AI_CONTROL)
			if(src.aiControlDisabled == 0)
				src.aiControlDisabled = 1
			else if(src.aiControlDisabled == -1)
				src.aiControlDisabled = 2
			src.updateDialog()
			spawn(10)
				if(src.aiControlDisabled == 1)
					src.aiControlDisabled = 0
				else if(src.aiControlDisabled == 2)
					src.aiControlDisabled = -1
				src.updateDialog()
		if(AIRLOCK_WIRE_ELECTRIFY)
			//one wire for electrifying the door. Sending a pulse through this electrifies the door for 30 seconds.
			if(src.secondsElectrified==0)
				src.secondsElectrified = 30
				spawn(10)
					//TODO: Move this into process() and make pulsing reset secondsElectrified to 30
					while (src.secondsElectrified>0)
						src.secondsElectrified-=1
						if(src.secondsElectrified<0)
							src.secondsElectrified = 0
//						src.updateUsrDialog()  //Commented this line out to keep the airlock from clusterfucking you with electricity. --NeoFite
						sleep(10)
		if(AIRLOCK_WIRE_OPEN_DOOR)
			//tries to open the door without ID
			//will succeed only if the ID wire is cut or the door requires no access
			if(!src.requiresID() || src.check_access(null))
				if(src.density)
					open()
				else
					close()
		if(AIRLOCK_WIRE_LIGHT)
			src.safetylight = !src.safetylight
		if(AIRLOCK_WIRE_HOLDOPEN)
			src.holdopen = !src.holdopen

/obj/machinery/door/secure/proc/mend(var/wireColor)
	var/wireFlag = WireColorToFlag[wireColor]
	var/wireIndex = WireColorToIndex[wireColor] //not used in this function
	wires |= wireFlag
	switch(wireIndex)
		if(AIRLOCK_WIRE_MAIN_POWER1, AIRLOCK_WIRE_MAIN_POWER2)
			if ((!src.isWireCut(AIRLOCK_WIRE_MAIN_POWER1)) && (!src.isWireCut(AIRLOCK_WIRE_MAIN_POWER2)))
				src.regainMainPower()
				src.shock(usr, 50)
				src.updateUsrDialog()
		if (AIRLOCK_WIRE_BACKUP_POWER1, AIRLOCK_WIRE_BACKUP_POWER2)
			if ((!src.isWireCut(AIRLOCK_WIRE_BACKUP_POWER1)) && (!src.isWireCut(AIRLOCK_WIRE_BACKUP_POWER2)))
				src.regainBackupPower()
				src.shock(usr, 50)
				src.updateUsrDialog()
		if (AIRLOCK_WIRE_AI_CONTROL)
			//one wire for AI control. Cutting this prevents the AI from controlling the door unless it has hacked the door through the power connection (which takes about a minute). If both main and backup power are cut, as well as this wire, then the AI cannot operate or hack the door at all.
			//aiControlDisabled: If 1, AI control is disabled until the AI hacks back in and disables the lock. If 2, the AI has bypassed the lock. If -1, the control is enabled but the AI had bypassed it earlier, so if it is disabled again the AI would have no trouble getting back in.
			if (src.aiControlDisabled == 1)
				src.aiControlDisabled = 0
			else if (src.aiControlDisabled == 2)
				src.aiControlDisabled = -1
			src.updateUsrDialog()
		if (AIRLOCK_WIRE_ELECTRIFY)
			if (src.secondsElectrified == -1)
				src.secondsElectrified = 0

/obj/machinery/door/secure/proc/isElectrified()
	if(src.secondsElectrified != 0)
		return 1
	return 0

/obj/machinery/door/secure/proc/isWireColorCut(var/wireColor)
	var/wireFlag = airlockWireColorToFlag[wireColor]
	return ((src.wires & wireFlag) == 0)

/obj/machinery/door/secure/proc/isWireCut(var/wireIndex)
	var/wireFlag = airlockIndexToFlag[wireIndex]
	return ((src.wires & wireFlag) == 0)

/obj/machinery/door/secure/proc/canAIControl()
	return ((src.aiControlDisabled!=1) && (!src.isAllPowerCut()));

/obj/machinery/door/secure/proc/canAIHack()
	return ((src.aiControlDisabled==1) && (!hackProof) && (!src.isAllPowerCut()));

/obj/machinery/door/secure/proc/arePowerSystemsOn()
	return (src.secondsMainPowerLost==0 || src.secondsBackupPowerLost==0)

/obj/machinery/door/secure/requiresID()
	return !(src.isWireCut(AIRLOCK_WIRE_IDSCAN) || aiDisabledIdScanner)

/obj/machinery/door/secure/proc/getAirlockWires()
	var/t1
	var/iterator = 0
	for(var/wiredesc in wire_index)
		if(iterator == wirenum)
			break
		var/is_uncut = src.wires & WireColorToFlag[wire_index[wiredesc]]
		t1 += "[wiredesc] wire: "
		if(!is_uncut)
			t1 += "<a href='?src=\ref[src];wires=[wire_index[wiredesc]]'>Mend</a>"
		else
			t1 += "<a href='?src=\ref[src];wires=[wire_index[wiredesc]]'>Cut</a> "
			t1 += "<a href='?src=\ref[src];pulse=[wire_index[wiredesc]]'>Pulse</a> "
			if(src.signalers[wire_index[wiredesc]])
				t1 += "<a href='?src=\ref[src];remove-signaler=[wire_index[wiredesc]]'>Detach signaler</a>"
			else
				t1 += "<a href='?src=\ref[src];signaler=[wire_index[wiredesc]]'>Attach signaler</a>"
		t1 += "<br>"
		iterator++
	return t1


