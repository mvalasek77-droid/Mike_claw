# BareClaw — Claude Code Notes

## Syncing to Mac / Opening in Xcode

Always use this command — it avoids all merge/conflict issues:

```bash
cd ~/Mike_claw && git fetch origin && git reset --hard origin/claude/add-personalities-avatars-EGPjs && open BareClaw.xcodeproj
```

Then ⌘B to build, ⌘R to run.

## Active branch

`claude/add-personalities-avatars-EGPjs`

## Project structure

- 66 Swift source files in `BareClaw/`
- All files must be registered in `BareClaw.xcodeproj/project.pbxproj` — if a new file is added, add it to PBXFileReference, PBXBuildFile, PBXGroup children, and PBXSourcesBuildPhase
