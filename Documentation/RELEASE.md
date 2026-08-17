# ScoreMaker release process

Release builds must pass the same compatibility suite used in development, use hardened-runtime
Developer ID signing, pass Apple's notarization service, carry a stapled ticket, and pass Gatekeeper
assessment.

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Run `make test`, then run the Xcode `ScoreMakerCompatibilityTests` scheme and inspect both
   complete compatibility-suite results.
3. Configure a Developer ID certificate and a `notarytool` keychain profile.
4. Set `SCOREMAKER_SIGN_IDENTITY` and `SCOREMAKER_NOTARY_PROFILE`.
5. Run `tools/release.sh`.
6. Launch the archived application on a clean macOS account and exercise open, save, autosave,
   undo/redo, playback, mixer mute/solo/pan, printing, forced page breaks, PDF and audio/stem export,
   MusicXML round trip, MIDI input, and Audio Unit fallback.
7. Complete a keyboard-only and VoiceOver smoke test of the inspector, transport, parts/mixer
   window, page-layout sheet, export panels, and all menu commands.

The script produces a universal optimized Xcode build, then fails before distribution if tests,
signing, notarization, stapling validation, or Gatekeeper assessment fail. Credentials remain in
the developer keychain and are never written into the repository.
