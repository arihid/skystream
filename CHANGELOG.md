# Changelogs - v2.7.6

### ✨ *New Features & Enhancements*

#### 🎬 Media Player & Subtitle Enhancements (PR #75 by @arranoust & PR #81 by @likhithkrishna1103)
- **Player Control Toggles** – Added customizable visibility toggles for player control buttons in player settings.
- **Cache Management** – Added dedicated setting to clear image and video cache.
- **Hotstar-Style Subtitles** – Replaced custom subtitle view with configurable Hotstar-style subtitle rendering and improved subtitle parsing robustness.

#### 📱 iOS Experience & Download Management (PR #84 by @Fares669)
- **iOS Live Activity & Background Downloads** – Integrated Live Activity for active downloads and iOS background task processing to ensure download tasks continue reliably when the app is backgrounded.
- **Detailed Download Progress** – Real-time download percentage and transferred file size indicators with improved label positioning.

#### 📑 Episode Selection & Watch History (PR #84 by @Fares669)
- **Multi-Episode Selection & Watched States** – Easily select multiple episodes to batch-mark as watched or unwatched.
- **Offline Watch History Sync** – Automatically sync playback of downloaded offline episodes with your episode watch history.
- **Improved Action Bar** – Replaced episode selection SnackBar with a dedicated bottom action bar and compact buttons.
- **Quick Copy Title** – Long press on any media title to quickly copy it to clipboard.

#### ⚙️ Poster Customization & Extension Settings (PR #74 by @arranoust & PR #84 by @Fares669)
- **Poster Title Positioning** – Added customizable title placement options (top, bottom, overlay) for multimedia poster cards.
- **Redesigned Extension Settings** – New dedicated plugin settings screen supporting conditional and script-defined plugin parameters, dynamic loading, and improved runtime cache handling.
- 
---

### 🐞 *Bug Fixes & System Stability*
- 🛠️ Fixed SnackBar contrast and theme colors across settings and download screens.
- 🛠️ Fixed extension settings runtime cache handling and plugin provider initialization.
