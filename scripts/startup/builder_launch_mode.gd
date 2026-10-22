extends RefCounted
## Regular builder startup is the default. Pilot enrollment configuration alone
## must not opt a normal editor or release launch into the classroom flow.

static func resolve(user_args: PackedStringArray, pilot_build_feature: bool = false) -> bool:
	return pilot_build_feature or user_args.has("--pilot")
