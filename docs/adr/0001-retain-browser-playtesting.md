# Retain browser playtesting alongside Windows downloads

Swordster's Godot port must preserve both playable browser builds and standalone
Windows downloads so testers can choose a link without installing development
tools or extracting a desktop build. A Windows-only port would reduce platform
validation work, but browser access is an explicit user requirement; the extra
browser input, audio, hosting and device validation work is accepted as part of
the port. This constrains language selection: the checked Godot 4 stable
documentation says C# projects cannot export to Web, so the language recommendation
is typed GDScript, subsequently accepted in [the language decision](0002-use-typed-gdscript.md).
See [the export research](../godot-export-research.md) for sources.
