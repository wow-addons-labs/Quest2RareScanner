# Quest2RareScanner

[中文](README.md) | [English](README.en.md)

Quickly add Questie quest targets to RareScanner tracking. Built for finding:

- Moving quest-item droppers
- Moving quest turn-in NPCs
- Quest targets with multiple spawn points

The addon **never adds anything automatically**. You decide when and what to add. RareScanner handles proximity alerts; the addon removes stale tracking as the quest state changes.

## Features

### World map: Alt + Left Click

Open the world map, hold `Alt` and left-click a Questie icon:

| Icon | Added to RareScanner |
|---|---|
| Kill / drop objective | The matching quest mob |
| Quest giver | The quest giver |
| Quest turn-in | The turn-in NPC |
| Item-started quest | NPCs that drop the starting item |
| Questie manual NPC note | That NPC |
| Ground object / event / minimap | Not supported |

- Writes all spawn points and patrol paths for the NPC
- Patrol targets show “Patrol: N paths”
- Multi-spawn targets show “Known N spawn locations”
- Fixed single-point targets have no extra location label

### Quest log: skull button

Open the quest log (L) and select an accepted quest. A RareScanner skull button appears at the top-right of the detail panel.

- **In progress**: choose “Kill / drop targets” and/or “Quest turn-in”
- **Ready to turn in**: only “Quest turn-in” is shown
- Every mob has its own checkbox, so you can track just one
- Everything is selected by default; the scroll bar only appears when the list overflows

### Automatic removal

| Quest state | What the addon does |
|---|---|
| Quest accepted | Removes the quest giver from tracking |
| Ready to turn in | Removes kill / drop targets, keeps the turn-in NPC |
| Turned in / abandoned | Removes all tracking for that quest |
| Item-started quest accepted | Removes the starting-item droppers |

- Changes during combat are deferred until combat ends
- Re-login or reload reconciles tracking against the current quest state
- NPCs already in RareScanner's built-in database are not added twice

### Minimap button

- Questie quest icon + RareScanner skull badge
- **Left click**: delete all tracking added by this addon
- **Right click**: help / status
- **Drag**: move the button

## Dependencies

| Addon | Purpose | Required |
|---|---|---|
| Questie | Map icons, quest objectives, spawn points, patrol paths, ZoneDB | Yes |
| QuestieDB | LibQuestieDB: NPC, quest, and item data | Yes |
| RareScanner | Custom NPC import/delete, proximity alerts | Yes |

The TOC declares them with `## RequiredDeps`. If any dependency is missing, the game reports a missing dependency and the addon does not load.

## Installation

Install these first:

- Questie
- QuestieDB
- RareScanner

Download `Quest2RareScanner-<version>.zip` from Releases and extract it to:

```text
World of Warcraft/_forever_/Interface/AddOns/
```

The final path should be:

```text
.../AddOns/Quest2RareScanner/Quest2RareScanner.toc
```

Then `/reload`.

## Usage

World map:

1. Open the world map and find a Questie icon.
2. Hold `Alt` and left-click it.
3. Check the chat report for the NPCs and their location type.
4. When you get close, RareScanner shows its alert and plays a sound.
5. When the quest state changes, the addon removes targets you no longer need.

Quest log:

1. Open the quest log and select an accepted quest.
2. Click the skull button at the top-right of the detail panel.
3. Tick the kill / drop targets and/or turn-in NPCs you want.
4. Click “Add”.

## Troubleshooting commands

You do not need commands for normal use; these are for diagnostics:

```text
/q2rs          show status
/q2rs delete   delete all tracking added by this addon (same as minimap left-click)
/q2rs debug    print the current quest and tracking data
```

## FAQ

**Why does clicking an icon do nothing?**  
It may be a ground-object or event icon; RareScanner does not support custom objects. Questie may also be missing data for that NPC.

**Why does it say “already included”?**  
The NPC is already in RareScanner's built-in database and does not need to be added as a custom NPC. Check RareScanner's NPC filters and scanning settings.

**Why are map icons still visible after deletion?**  
They may be RareScanner's recently-seen markers, which last up to 2 minutes (30 minutes in instances). They may also be Blizzard's own rare icons, which this addon cannot control.

**Which client is supported?**  
WoW Forever 1.60.1 only.

## Author / License

Luomo, MIT License.
