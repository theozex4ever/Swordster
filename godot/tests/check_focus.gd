class_name CheckFocus
extends RefCounted
## `--focus=<group>[,<group>]` (a user argument after `--`, see run_checks.gd) runs only the named
## check groups, so the mutation checker can try the group a mutation belongs to first and
## reject it in a second or two. A group is named by its file name without `_checks.gd`
## ("warden_maelstrom"); `--focus=none` runs no group at all, only run_checks.gd's own checks.
## Every group's `run_all()` starts with `if not CheckFocus.includes("<its name>"): return`; the render-rate
## group (render_rate_checks.gd) is `--focus=render_rate`. A
## group without that line still runs, so a missing line costs time, never correctness.
## Without `--focus` every group runs. A run with ANY `--focus` is only partial evidence, so
## run_checks.gd reports it as "CHECKS PARTIAL", never "CHECKS PASSED" (see `active()`).


static func includes(group: String) -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--focus="):
			return argument.trim_prefix("--focus=").split(",").has(group)
	return true


## True when the run was started with a `--focus=` argument, whatever it names.
static func active() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--focus="):
			return true
	return false
