# Wordie

A lightweight macOS menubar app for refining text with Claude. Copy text to your clipboard, launch Wordie, tweak your prompt, and review a word-level diff before accepting or rejecting the changes.

## Installation

**Requirements:** macOS 13+ and an [Anthropic API key](https://console.anthropic.com). Building requires Swift 5.9+ (Xcode 15+ or [swift.org](https://swift.org/download/)).

**Build and install:**

```
git clone <repo-url>
cd wordie
swift build -c release
cp .build/release/Wordie /usr/local/bin/wordie
```

**Or just run from source:**

```
swift run Wordie
```

**API key:** On first launch, open **Wordie → Settings** (⌘,) and paste your Anthropic API key. It's stored in UserDefaults and only needs to be set once.

## How It Works

1. **Launch / Summon.** Wordie reads your system clipboard and loads the text into an editable text area. The app stays running in the background when you close the window — press ⌃⌥W from anywhere to summon it back (clipboard is reloaded automatically). You can also click the Dock icon.
2. **Edit the prompt.** The prompt field above the text area defaults to *"Tighten up this text to keep the tone and meaning."* Change it to whatever instruction you want Claude to follow.
3. **Process** (⌘↩). Sends your text and prompt to Claude. The text area grays out and a spinner appears while the request is in flight.
4. **Review the diff.** The text area is replaced by a word-level diff. Removed words appear in red with a strikethrough; added words appear in green with a highlight. The diff is inline — old and new words are interleaved in reading order, not split into separate columns or lines.
5. **Edit the diff.** The green (added) and white (unchanged) text is directly editable. Red (removed) text is locked. Any edits you make update the "new text" and the diff recomputes live against the original, so the red/green/white coloring always reflects the true difference. Cursor position is preserved across recomputations.
6. **Navigate diff sites.** Use ⌘J/⌘K to jump between diff sites (contiguous chunks of changes). The selected site is highlighted with inverted colors — white text on solid red/green backgrounds.
7. **Accept or reject individual sites.** Press ⌘Y to accept the selected site (its new text becomes part of the baseline) or ⌘N to reject it (the old text is restored for that site). The site disappears from the diff and selection moves to the next site.
8. **Accept All** (⌘↩) accepts all remaining changes and copies the result to your clipboard. **Reject All** (Esc) reverts all remaining changes. Either way, you're back to the editing state and can process again.

## Keyboard Shortcuts

| Key | Context | Action |
|-----|---------|--------|
| ⌘↩ | Editing | Process text with Claude |
| ⌘↩ | Reviewing | Accept all remaining changes |
| Esc | Reviewing | Reject all remaining changes |
| ⌘J | Reviewing | Jump to next diff site |
| ⌘K | Reviewing | Jump to previous diff site |
| ⌘Y | Reviewing | Accept selected diff site |
| ⌘N | Reviewing | Reject selected diff site |
| ⌘W | Any | Hide window (app stays running) |
| ⌃⌥W | Global | Summon Wordie from any app |
| ⌘, | Any | Open Settings |

## Code Overview

The project is a Swift Package Manager executable with six source files under `Sources/Wordie/`. There are no external dependencies.

**WordieApp** is the SwiftUI app entry point. It defines the main window, wires up the Settings scene (for the API key panel), and uses an `AppDelegate` for lifecycle management. The AppDelegate registers a global hotkey (⌃⌥W) via the Carbon `RegisterEventHotKey` API, adds a Close Window (⌘W) menu item that hides rather than destroys the window, and handles dock-icon reopening. The app does not quit when the window is closed.

**ContentView** is the main view and owns all the application state. It tracks a three-phase state machine — *editing*, *processing*, and *reviewing* — that determines which UI elements are visible: the editable text area and Process button, a loading spinner, or the editable diff view with Accept All/Reject All buttons. It reads the system clipboard on appear and whenever the window regains focus while in the editing state (so summoning Wordie picks up freshly copied text). When the user hits Process, it kicks off an async task that calls the API and transitions to the reviewing state. Accept All copies the result to the clipboard; Reject All restores the original.

**ClaudeAPI** is a thin wrapper around `URLSession` that sends a single messages-API request to Claude (model `claude-sonnet-4-20250514`). It constructs the prompt to ask Claude to return only the updated text with no preamble. It validates the API key is present before making the request and maps HTTP errors into user-facing error messages.

**DiffEngine** computes a word-level diff between two strings. It first tokenizes each string into alternating runs of word characters and whitespace, then finds the longest common subsequence of those tokens using a dynamic-programming table. It walks the LCS against both token lists to emit a sequence of `unchanged`, `added`, and `removed` tokens.

**SettingsView** is a simple form with a secure text field for the API key, backed by `@AppStorage` so it persists in UserDefaults. A show/hide toggle lets you reveal the key for verification.

**EditableDiffView** is an `NSViewRepresentable` that bridges to an `NSTextView` for the diff display. It uses a Coordinator as the text view's delegate to manage editing. Each diff token is rendered as a styled run in an `NSAttributedString`, with a custom attribute marking removed text. The delegate's `shouldChangeTextIn` blocks any edit that touches a removed range. On each edit, `textDidChange` extracts the "new text" by concatenating all non-removed content from the text storage, updates the binding, recomputes the diff via `DiffEngine`, and reapplies the attributed string. Cursor position is preserved across recomputations by converting to and from a "new text offset" that counts only non-removed characters.
