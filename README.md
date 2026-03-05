# Wordie

A lightweight macOS app for quickly refining text with Claude. Copy text to your clipboard, launch Wordie, tweak your prompt, and review a word-level diff of Claude's suggestions before accepting or rejecting them.

## Installation

**Requirements:** macOS 13 (Ventura) or later. Building from source requires Swift 5.9+, which comes with Xcode 15+ or can be installed standalone from [swift.org](https://swift.org/download/).

### Option 1: Build and install

Clone the repo and build a release binary:

```
git clone <repo-url>
cd wordie
swift build -c release
```

Copy the binary somewhere on your PATH:

```
cp .build/release/Wordie /usr/local/bin/wordie
```

Then launch it from anywhere:

```
wordie
```

### Option 2: Run from source

If you just want to try it without installing:

```
cd wordie
swift run Wordie
```

This builds a debug version and runs it immediately.

### API key

On first launch, open **Wordie → Settings** (⌘,) and paste your Anthropic API key. The key is persisted in macOS UserDefaults so you only need to do this once. You can get a key from [console.anthropic.com](https://console.anthropic.com). If the key is missing or invalid when you hit Process, an error message will appear in the main window.

## How It Works

1. **Launch.** Wordie reads your system clipboard and loads the text into an editable text area.
2. **Edit the prompt.** The prompt field above the text area defaults to *"Tighten up this text to keep the tone and meaning."* Change it to whatever instruction you want Claude to follow.
3. **Process** (⌘↩). Sends your text and prompt to Claude. The text area grays out and a spinner appears while the request is in flight.
4. **Review the diff.** The text area is replaced by a word-level diff. Removed words appear in red with a strikethrough; added words appear in green with a highlight. The diff is inline — old and new words are interleaved in reading order, not split into separate columns or lines.
5. **Accept** (⌘↩) replaces the text with Claude's version and copies it to your clipboard. **Reject** (Esc) restores the original text. Either way, you're back to the editing state and can process again.

## Code Overview

The project is a Swift Package Manager executable with five source files under `Sources/Wordie/`. There are no external dependencies.

**WordieApp** is the SwiftUI app entry point. It defines the main window, wires up the Settings scene (for the API key panel), and uses an `AppDelegate` to ensure the app quits when the window closes.

**ContentView** is the main view and owns all the application state. It tracks a three-phase state machine — *editing*, *processing*, and *reviewing* — that determines which UI elements are visible: the editable text area and Process button, a loading spinner, or the diff view with Accept/Reject buttons. On appear, it reads the system clipboard via `NSPasteboard`. When the user hits Process, it kicks off an async task that calls the API, computes the diff, and transitions to the reviewing state. Accept copies the result to the clipboard; Reject restores the original.

**ClaudeAPI** is a thin wrapper around `URLSession` that sends a single messages-API request to Claude (model `claude-sonnet-4-20250514`). It constructs the prompt to ask Claude to return only the updated text with no preamble. It validates the API key is present before making the request and maps HTTP errors into user-facing error messages.

**DiffEngine** computes a word-level diff between two strings. It first tokenizes each string into alternating runs of word characters and whitespace, then finds the longest common subsequence of those tokens using a dynamic-programming table. It walks the LCS against both token lists to emit a sequence of `unchanged`, `added`, and `removed` tokens.

**SettingsView** is a simple form with a secure text field for the API key, backed by `@AppStorage` so it persists in UserDefaults. A show/hide toggle lets you reveal the key for verification.

The diff is rendered in ContentView by **WrappingHStack**, an `NSViewRepresentable` that bridges to an `NSTextView`. It builds an `NSAttributedString` with colored, styled runs for each diff token, which gives proper word wrapping and text selection that SwiftUI's `Text` concatenation can't easily provide.
