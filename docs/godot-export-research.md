# Godot export research

Verified 2026-11-08 against official English **stable** documentation only. Documentation review; no Godot build or tester-device validation performed. The `stable` alias can change, so pin an editor release and matching templates during implementation.

## Recommendation

Use **typed GDScript, the standard editor, and Compatibility rendering** for the Swordster port. This is a recommendation based on the Windows/browser delivery requirement: Godot 4 C# projects cannot export to Web. C# does support Windows, but cannot supply both requested targets. [C# platform support](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/index.html#c-platform-support)

Typed GDScript supports variable, parameter, and return types, catches more errors before execution, improves completion, and uses optimized opcodes for known types. This supports maintainability; it does not establish a performance comparison with C# or prove this game's frame rate. [Static typing](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)

## Tooling and Windows builds from Linux

- The standard executable has no C# support; C# requires the .NET editor. Building C# also requires a separately installed .NET SDK; exported compiled games bundle the required runtime parts. The built-in C# editor is minimal, so the docs recommend an external editor. Typed GDScript avoids that extra .NET toolchain. [C#/.NET](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/index.html), [C# prerequisites](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html#prerequisites)
- Install export templates for the chosen editor release and target architecture, then create a Windows export preset. Export Project produces the executable plus game data; Export PCK/ZIP alone does not produce a playable build. [Export templates and presets](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)
- Linux-to-Windows delivery uses the Linux editor with Windows templates, rather than compiling Windows binaries locally. This follows the documented template-based export workflow and host-independent CLI; no Wine/Python packaging toolchain is specified for standard Windows export. Windows defaults to x86_64. Send the complete exported output (including its PCK when separate) in a ZIP. [Windows export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html), [CLI export](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html#exporting)

Illustrative command once a Godot project, preset named `Windows Desktop`, templates, and output directory exist (not run):

```sh
godot --headless --path /path/to/project --export-release "Windows Desktop" builds/Swordster.exe
```

The command requires an editor binary; the preset name must match `export_presets.cfg`, and the target directory must already exist. [Command-line reference](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html#command-line-reference)

## Browser hosting and audio

- Web requires WebAssembly and WebGL 2.0 through Compatibility; Forward+/Mobile are unsupported. Single-thread export is the preferred default: disable Thread Support and Extensions Support for simple hosting. It sacrifices threading and some performance. [Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- Serve all generated files together over HTTP(S), with `.wasm` as `application/wasm`; use HTTPS for shared hosting. Single-thread export avoids the SharedArrayBuffer isolation requirement. Threads or extensions require cross-origin isolation; threaded hosting needs COOP `same-origin`, COEP `require-corp`, and a secure context (or the documented PWA workaround). [Hosting and thread support](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#serving-the-files)
- Default Web **Sample** audio offers low latency without threads, but lacks AudioEffects, reverb, Doppler, and procedural generation; positional audio has caveats. **Stream** restores Godot audio features with higher latency, especially without threads. Browsers may require a click/tap/key before audio starts. [Audio playback](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#audio-playback), [Autoplay](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#audio)
- Port implication: bake the existing synthesized effects into audio assets for Sample playback, or validate Stream latency before committing to runtime synthesis. This is a recommendation, not a measured result.

## Remaining Windows signing friction

Exporting does not provision a signing identity. Automatic signing still requires a package-signing certificate and an external tool: Windows SDK SignTool on Windows, or `osslsigncode` on Linux/other hosts. Configure the editor's signing-tool path and enable signing with the certificate identity in the Windows preset. Certificate acquisition and configuration remain distribution work regardless of scripting language. [Windows code signing](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html#code-signing)

These stable docs do not promise that signing eliminates SmartScreen or antivirus warnings. No such guarantee, certificate price, or reputation timeline is asserted here. A Windows tester smoke test remains necessary.
