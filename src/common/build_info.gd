class_name BuildInfo
## The build's version, as testers should quote it in feedback.
##
## The number lives in Project Settings > Application > Config > Version (`application/config/version`).
## The Windows export reads the same setting for the exe's file and product version (its own fields are
## left empty), so bumping it once before an export updates the exe, the title screen and the pause menu.

const FALLBACK: String = "0.0.0"


static func version() -> String:
	var value: String = String(ProjectSettings.get_setting("application/config/version", ""))
	return value if not value.is_empty() else FALLBACK


## "v0.1.0", plus "debug" for a debug build, so a report from an editor run can't pass for a release.
static func version_text() -> String:
	return "v%s%s" % [version(), "" if not OS.is_debug_build() else " debug"]
