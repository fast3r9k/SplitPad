# SplitPad

SplitPad 0.6.1 is an iPad keyboard with English and Russian layouts, split and joined modes, four rows of keys, alternate characters, word suggestions, emoji, and size controls accessible directly from the keyboard.

It is a custom keyboard extension that iPadOS loads in place of the system keyboard. It does not modify Apple's keyboard.

## Install on your iPad

1. Open `SplitPad.xcodeproj` in Xcode.
2. If you have not added your Apple Account yet, go to **Xcode → Settings → Accounts → + → Apple Account**.
3. Select the blue project icon in the navigator. Under **TARGETS**, select **SplitPad → Signing & Capabilities**. Enable **Automatically manage signing** and select your **Team**. For a free account, select your **Personal Team**.
4. Select the same team for the **SplitPadKeyboard** target.
5. If Xcode reports that the bundle identifier is unavailable, replace `com.nikitagreckin.ThumbSplit` with a unique identifier, such as `com.yourname.SplitPad2026`. Use the same prefix followed by `.Keyboard` for the extension: `com.yourname.SplitPad2026.Keyboard`.
6. Connect your iPad to your Mac, unlock it, and trust the computer if prompted.
7. If Xcode asks you to enable **Developer Mode**, open **Settings → Privacy & Security → Developer Mode** on your iPad. You will need to restart the iPad and confirm the change.
8. In Xcode's toolbar, select the **SplitPad** scheme and your iPad as the run destination. Click ▶︎ or press **⌘R**.
9. If the iPad asks you to trust the developer, go to **Settings → General → VPN & Device Management → Developer App → Trust**. This option appears only when the system requires it.
10. Add the keyboard in **Settings → General → Keyboard → Keyboards → Add New Keyboard → SplitPad**. **Allow Full Access** is not required.
11. Open the SplitPad app, tap the test field, and hold the globe key on the onscreen keyboard. Select **SplitPad**.

With a free Personal Team, the provisioning profile expires after seven days. Rebuild and reinstall the app from Xcode when it expires. App Store distribution is not required for personal testing. See Apple's [developer account information](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Usage

- Tap the rectangle button next to the right space bar to join or split the keyboard. In joined mode, this button sits to the right of the single space bar.
- Hold that button to open settings for the width of each half, key height, and key clicks. Settings are saved locally. There is no separate gear button; colors automatically follow the system theme and the text field's appearance.
- The `.?123` keys on both sides open numbers and symbols. Joined mode has one such key.
- Pressing Space on the numbers and symbols page returns to letters in the current language. This also works while searching for emoji.
- Tap 🌐 to switch languages. Hold 🌐 to switch to the next iPadOS keyboard. The right edge of each space bar shows `eng` or `ру`.
- `Tab`, at the start of the second row, inserts a tab character. Its appearance depends on the host app; it does not move focus to the next field.
- The first letter of a sentence is capitalized automatically, subject to the text field's settings. For example, a field may disable automatic capitalization.
- Quickly press Space twice after a word to insert a period and a space (`. `). Double-tap Shift to enable Caps Lock, indicated by a line beneath the arrow. Tap Shift once to turn it off.
- Alternate characters on letter keys are available only in the top row. Letters in the second and third rows have neither corner labels nor alternate-character menus. The comma and period keys retain their alternatives.
- Enter the character shown in a key's upper-right corner by swiping down, or by holding and releasing without moving. The Russian `е` key shows `5` in its corner and offers two options when held: `5` and `ё`.
- Hold a letter or symbol key with alternatives to open its menu above the key, including in the top row. The secondary character is selected initially; slide your finger to another option and release to enter it. Find `ё` under `е`, accented characters under English top-row letters, and currencies, quotation marks, and dashes on the symbols page. Curly braces are available under square brackets.
- Backspace deletes one character immediately, then repeats. After 1.6 seconds of holding, it starts deleting whole words. Releasing or moving your finger off the key stops deletion.
- The keyboard adapts when you rotate the iPad. In narrow windows, the gap between the two halves becomes smaller.
- Key clicks use the system sound mechanism and also depend on the iPad's sound settings.
- Up to three suggestions appear above the keys: spelling corrections, completions for the current word, or simple next-word suggestions. Russian and English corrections are labeled **Исправить** / **Correct** and are applied only when tapped. The word before the cursor is checked, including immediately after a space or punctuation; existing spaces and punctuation are preserved. To correct an earlier word, place the cursor immediately after it. Text is never replaced automatically.
- Tap the smiley to the right of the globe to open the Emoji 18 catalog, with Russian and English names from CLDR 49. Scroll emoji horizontally; categories and recent emoji are available in the bottom bar. Tap `АБВ` / `ABC` to return to letters.
- Tap the search bar and enter a name or keywords in Russian or English. Use the globe to switch languages. Search takes place entirely within the keyboard: the query is neither inserted into the host app nor saved. Tap a result to insert the emoji into the original text field. **Отмена** (Cancel) or **Готово** (Done) returns to the full catalog.
- Hold an emoji that has variants, slide your finger to a skin tone, and release. Couple emoji support separate skin tones for each person. The selected variant is remembered for that emoji.
- **Recents** keeps the last 40 selected emoji, including skin tones, without duplicates. This history is stored only in the extension's local settings.
- The catalog contains 3,963 fully qualified sequences grouped into 1,923 base emoji. Skin-tone and hair modifiers are not shown as standalone emoji. The panel displays symbols that the installed Apple font can render as a single emoji; support for newer emoji depends on the iPadOS version.

## Limitations

- There is no automatic correction or continuous swipe typing. Built-in dictation is not available; switch to the system keyboard using the globe for voice input. Spelling and word completion use local UIKit dictionaries. When a dictionary marks a word as misspelled, close matches from a small common-word list receive priority. The availability and quality of corrections depend on the dictionary for the selected language. Next-word suggestions use a small set of rules; they are not Apple's predictive text system or a learning model. The host app, not the keyboard extension, controls spelling underlines in the text field.
- Suggestions are not offered in numeric, email, or URL fields, when text is selected, or when the cursor is inside a word. Word completion respects the field's autocorrection setting; corrections respect its spell-checking setting. Addresses, mixed-script words, and words containing digits are not corrected. Text is neither sent over the network nor saved for learning.
- iPadOS switches to the system keyboard in password fields and some phone-number fields. Apps can also disallow third-party keyboards entirely.
- The gap between the halves remains part of the keyboard's overall area. The halves are not independent floating windows, and the gap is not a transparent area through which you can interact with the app.
- If the host app hides the input context, double-space does not replace text, and accelerated deletion remains character by character. Initial capitalization follows the field's settings; if context is consistently unavailable, you may need to use Shift manually.
- The keyboard does not send text over the network or save typed messages or search queries. Recent emoji and preferred skin tones are stored locally. **Full Access** is not required.

## Development

The app was previously named ThumbSplit. Its original bundle identifiers and emoji-history storage key are retained so updates preserve existing installations and preferences. Select your own signing team and unique bundle identifiers when building a fork.

- Minimum version: **iPadOS 17.0**. The project targets iPad, uses Swift 5 language mode, SwiftUI for the containing app, and UIKit for the keyboard extension.
- `SplitPadApp/SplitPadApp.swift` — setup instructions and a test field.
- `KeyboardExtension/KeyboardViewController.swift` — sizing, settings, and interaction with the text field.
- `KeyboardExtension/KeycapView.swift` — taps, downward swipes, and alternate-character menus.
- `KeyboardExtension/KeyboardModel.swift` — layouts and editing logic independent of UIKit.
- `KeyboardExtension/KeyboardSuggestions.swift` — suggestion selection, safe replacement of misspelled words, and context validation before insertion.
- `KeyboardExtension/EmojiPanelView.swift` — categories, search, recents, and skin-tone selection.
- `KeyboardExtension/EmojiCatalog.swift` and `EmojiCatalog.json` — the local emoji catalog, search, and history.
- `Scripts/generate_emoji_catalog.py` — reproducible catalog updates from Unicode/CLDR. Sources are documented in [EmojiCatalogSources.md](KeyboardExtension/EmojiCatalogSources.md); the data license is in [LICENSE-UNICODE.txt](KeyboardExtension/LICENSE-UNICODE.txt).
- `Tests/KeyboardModelTests.swift` and `Tests/KeyboardSuggestionsTests.swift` — input logic, layout, and suggestion checks.
- `Tests/EmojiCatalogTests.swift` — catalog completeness against Unicode, Russian/English search, skin-tone variants, and history persistence.
- `KeyboardExtension/Info.plist` — keyboard extension registration without Full Access.
- `KeyboardExtension/PrivacyInfo.xcprivacy` — declarations for local UserDefaults usage and measuring tap and hold intervals.

Check the build without signing, from the project directory:

```sh
xcodebuild -project SplitPad.xcodeproj -scheme SplitPad -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

An unsigned build cannot be installed directly on an iPad. Use Xcode with your own signing team to install it.

Run the model checks from the project directory:

```sh
mkdir -p .build/ModelModuleCache
xcrun swiftc -parse-as-library -module-cache-path .build/ModelModuleCache KeyboardExtension/KeyboardModel.swift Tests/KeyboardModelTests.swift -o .build/keyboard-model-tests
.build/keyboard-model-tests
xcrun swiftc -parse-as-library -module-cache-path .build/ModelModuleCache KeyboardExtension/KeyboardModel.swift KeyboardExtension/KeyboardSuggestions.swift Tests/KeyboardSuggestionsTests.swift -o .build/keyboard-suggestion-tests
.build/keyboard-suggestion-tests
```

Check the catalog and history from the project directory. The first command downloads only the Unicode/CLDR source data needed for verification:

```sh
python3 Scripts/generate_emoji_catalog.py --source-dir .build/emoji-sources --download --check
xcrun swiftc -parse-as-library -module-cache-path .build/ModelModuleCache KeyboardExtension/EmojiCatalog.swift Tests/EmojiCatalogTests.swift -o .build/emoji-catalog-tests
.build/emoji-catalog-tests KeyboardExtension/EmojiCatalog.json .build/emoji-sources/emoji-test.txt
```

## Device testing

1. In an empty field, type `Привет`, quickly press Space twice, and continue typing. Expect `Привет. ` followed by a capitalized letter.
2. Double-tap Shift, type several letters, and disable Caps Lock. Check the line beneath the arrow in the Caps Lock icon.
3. Tap 🌐 to switch languages; hold 🌐 to switch to the next system keyboard. Check that Tab inserts a tab character.
4. Swipe down on the first letter key to enter `1`. Hold `е` / `e`, slide through the alternatives, and release. Repeat with currencies, quotation marks, and dashes.
5. Hold Backspace in a long test passage: characters should be deleted first, then words. Move your finger off the key; deletion should stop.
6. Join and split the keyboard. Check both orientations, light and dark themes, and size adjustments.
7. Test key clicks on an iPad with system keyboard sounds enabled. Reopen the keyboard and check that settings persist.
8. Test Russian and English suggestions, emoji insertion, returning to letters, switching fields, and placing the cursor inside a word.
9. Search for `кот` and `cat`. Verify that the query and Backspace do not change the host app's text, while selecting a result inserts it into that text. Check empty results, clearing, cancellation, and language switching.
10. Hold a hand gesture or couple emoji and select a skin tone by sliding your finger. Moving outside the menu should cancel selection. Open Recents, then reopen the keyboard: selected emoji and skin tones should persist. Check search and skin-tone menus after rotating the device.
11. Type `Превет` or `teh`, then select an **Исправить** / **Correct** suggestion. Repeat after a space and comma; punctuation and spacing should be preserved. Moving the cursor or switching fields or languages between pressing and releasing a suggestion should cancel the stale replacement.
12. On the numbers page, enter a number and a space; the current language's letters should return. Check both space bars, both languages, and emoji search. Lower-row letters should have neither small secondary labels nor hold menus.

When testing through Device Hub, disable **Device → Keyboard → Simulate Hardware Keyboard** so that the iPad does not treat a hardware keyboard as connected. **Toggle Software Keyboard** can restore the onscreen keyboard. If an already-open app shows an empty keyboard background immediately after installing a new build, close and reopen that app.

Apple documentation: [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard).

## Verification status

**Version 0.6.1 (build 13)** renames the app, keyboard, Xcode project, and shared scheme to SplitPad. Existing bundle identifiers and saved preferences remain compatible. The unsigned iOS build, all 101 emoji catalog/history checks, and the Unicode/CLDR catalog reproducibility check passed. The repository excludes local Xcode user settings and build outputs; signing requires selecting your own team.

**Version 0.6 (build 12)** was built and signed with Xcode 27.2 and installed on an iPad Pro 12.9-inch (M2) running iPadOS 27.2. All 226 checks for suggestions, corrections, ranking, and safe replacement passed. Device testing in SplitPad's test field confirmed tap-to-correct replacements of `Превет` → `Привет` and `teh` → `the`, preservation of case, commas, and spaces, no automatic replacement, and the return of normal suggestions after correction. Close common words supplement the system dictionary: `привет` is offered before `пресет`. The new spelling feature has not been separately tested in Telegram or other third-party apps.

**Version 0.5.1 (build 11)** removed the separate dictation screen, microphone button, URL handoff, and microphone and speech-recognition permission requests. The right-hand `.?123` key was restored. Lower-row letter alternatives remain removed, and pressing Space on the symbols page still returns to letters.

Version 0.5.1 was built and signed with Xcode 27.2 and installed on an iPad Pro 12.9-inch (M2) running iPadOS 27.2. All 152 input-model and layout checks passed. Device testing confirmed the removal of the dictation card and microphone, opening numbers with the right-hand `.?123` key, and returning to letters after entering `1` and pressing the right space bar. The built app contains no microphone or speech-recognition permissions and no dictation URL scheme. Earlier runs passed 70 suggestion checks, 101 emoji catalog, search, and history checks, and the catalog reproducibility check; those components were unchanged in that update.

In **version 0.4.3**, top-row alternate-character menus fit above their keys: menu height adapts to the available space, so menus no longer appear beneath the finger. Build and installation succeeded; entering `1` and `5` by holding top-row keys was rechecked on the iPad.

In **version 0.4.2**, the Russian `е` key regained its `5` corner label, and holding it offers only `5` and `ё`. All 148 model checks passed.

In **version 0.4.1**, physical-device testing covered entering `1`, `3`, `9`, `@`, and `+` by holding keys; entering `Ё` / `ё` by holding Russian `е`; ordinary short taps; and entering numbers with downward swipes. All displayed secondary characters are included in their hold menus.

In **version 0.4**, physical-device testing covered `кот` / `cat` search, result ordering and insertion, isolation of search input and Backspace from the host app's text, clearing and canceling search, language switching, categories, recents, selecting a skin tone through a hold followed by a tap, reusing the selected tone, and the menu of 26 handshake variants. History and skin tones survived reinstalling the update. Stale cells shown when switching from a category to Recents were fixed.

The emoji panel was tested in portrait and landscape orientations with the dark theme. Rotating the device sometimes dismisses the keyboard in SplitPad's own test field; tapping the field again reopens it. This is existing test-app behavior, and preserving an emoji search query across such a dismissal is not guaranteed. Skin-tone selection with one continuous finger movement and the new panel's light theme still need separate manual testing.

Physical-device testing also covered the layout, joining and splitting, themes, language switching, Caps Lock, double-space, entering numbers with downward swipes, and accented characters through hold menus. A text-field connection crash identified in a device report was fixed. Keyboard height no longer leaves the previous large empty area below the keys.

In **version 0.3**, additional physical-device checks covered suggestion and emoji insertion, returning to letters, opening settings by holding the mode button, the system dark theme, hiding and reopening the keyboard in SplitPad and Telegram, and switching between those apps. Device Hub's hardware-keyboard simulation was disabled during testing; Telegram required a restart after the extension update.

In **version 0.3.1**, physical-device checks covered Tab insertion, opening emoji with the button next to the globe, inserting emoji, and returning to letters. The new keys were tested in both split and joined layouts.

The full checklist of sliding gestures, sound, and behavior across third-party apps still requires further device testing.
