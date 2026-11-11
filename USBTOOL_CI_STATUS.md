# USBTool CI

The cloud build uses Android SDK Platform 36 because Platform 37 was not available from the hosted SDK package index during the first run. The workflow adjusts the app module compile SDK and target SDK to 36 for this build attempt. The Android runtime minimum remains API 24, so Android 10 (API 29) remains within the declared minimum range.
