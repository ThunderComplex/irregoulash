class_name NoiseKind
extends RefCounted
## What kind of sound a noise is, and how an enemy that hears it reacts.
##
## `GameDirector.make_noise` takes a `Type` alongside the radius: the radius says how far a sound
## carries, the type says what it means. A gunshot and a door creaking can be equally loud, but only
## one of them is a fight. The reactions are a table here rather than branches in `Enemy`, so
## retuning how the AI treats a sound is one line.

enum Type {
	## Walking, and the player's dash.
	FOOTSTEP,
	GUNSHOT,
	## A spell being cast. Reacts like a gunshot, kept apart so the two can be tuned separately.
	ABILITY,
	## A door opening or closing, or bouncing off someone standing in the doorway.
	DOOR,
	DOOR_SMASH,
	## A locked door being tried, or dashed into.
	DOOR_LOCKED,
}

## How an enemy responds to a sound from the player (or from no one in particular).
enum Reaction {
	## Straight to ALERT, heading for the sound, however far off it was and whether or not it was seen.
	ALERT,
	## Turn and look; never escalates to ALERT on its own.
	SUSPICIOUS,
	## Builds awareness with loudness and closeness, and only alerts once that fills up.
	BUILD_AWARENESS,
}


static func reaction(type: Type) -> Reaction:
	match type:
		Type.GUNSHOT, Type.ABILITY, Type.DOOR_SMASH:
			return Reaction.ALERT
		Type.DOOR, Type.DOOR_LOCKED:
			return Reaction.SUSPICIOUS
		_:
			return Reaction.BUILD_AWARENESS


static func type_name(type: Type) -> String:
	return Type.keys()[type]
