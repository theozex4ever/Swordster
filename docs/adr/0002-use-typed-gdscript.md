# Use typed GDScript for the Godot port

Swordster requires both browser playtesting and Windows downloads, and its current
Python prototype has no C# or .NET code to reuse. Use typed GDScript with Godot's
standard editor and Compatibility renderer: this preserves browser exports and
avoids the additional .NET build toolchain. C# offers stronger general-purpose
tooling and potential advantages for CPU-heavy simulation, but Godot 4 C# cannot
currently export to Web; those advantages do not outweigh losing a required
delivery target. Profile the actual port before considering a different language.
See [the export research](../godot-export-research.md) for the verified constraints.
