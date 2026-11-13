# LiveWall iOS

Needs a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
brew install xcodegen
cd ios && xcodegen        # creates LiveWall.xcodeproj
open LiveWall.xcodeproj
```
Then: set your Team ID in `project.yml` (or in Xcode → Signing), change `com.example` bundle IDs and the
App Group (`group.com.example.livewall`, also in `Shared/SharedStore.swift`) to yours, and set the Worker URL in
`App/Config.swift`. Run on a real iPhone (push doesn't work in the simulator).
Add the widget: long-press Lock Screen → Customize → add "Partner note" under the clock.
