# Contributing

This guide provides instructions for contributing to this Capacitor plugin.

## Developing

### Local Setup

1. Fork and clone the repo.
1. Install the dependencies.

    ```shell
    npm install
    ```

1. Install SwiftLint if you're on macOS.

    ```shell
    brew install swiftlint
    ```

### Scripts

#### `npm run build`

Build the plugin web assets and generate plugin API documentation using [`@capacitor/docgen`](https://github.com/ionic-team/capacitor-docgen).

It will compile the TypeScript code from `src/` into ESM JavaScript in `dist/esm/`. These files are used in apps with bundlers when your plugin is imported.

Then, Rollup will bundle the code into a single file at `dist/plugin.js`. This file is used in apps without bundlers by including it as a script in `index.html`.

#### `npm run verify`

Build and validate the web and native projects.

This is useful to run in CI to verify that the plugin builds for all platforms.

#### `npm run lint` / `npm run fmt`

Check formatting and code quality, autoformat/autofix if possible.

This template is integrated with ESLint, Prettier, and SwiftLint. Using these tools is completely optional, but the [Capacitor Community](https://github.com/capacitor-community/) strives to have consistent code style and structure for easier cooperation.

## Testing

```shell
npm test               # TypeScript (Vitest): the bridge, the web fallback, and that the API, both platforms and the README agree
npm run test:android   # Kotlin on the JVM (JUnit): option parsing and size arithmetic; needs JDK 21 and the Android SDK
npm run test:core      # Swift on the Mac (`swift test`, no simulator): the same, plus end-to-end transcodes of test/fixtures
npm run test:ios       # the Swift tests and the bridge's own on an iOS simulator; IOS_SIMULATOR_UDID picks one
npm run fixtures       # writes test/fixtures again with FFmpeg
```

The transcoding itself needs a phone's encoder to be checked for real. The example app does it: copy videos into its `in/` folder
(`Documents/in` on iOS, `Android/data/io.github.maximbelov.videotranscoder.example/files/in` on Android), start it, and read
`out/results.json` and the MP4s in `out/` back. Each case in the JSON is one call: what it was asked, what it answered, how long it
took and what progress it reported. Check the MP4s with `ffprobe`.

## Publishing

Releases are published by CI, not from a laptop: bump `version` in `package.json` in a pull request, and when it is merged to `main`,
`.github/workflows/ci.yaml` builds the package and publishes it to npm through trusted publishing. A merge that keeps the version
publishes nothing.

The Media3 version is pinned in `android/build.gradle`. `.github/workflows/pins.yaml` opens a pull request every Monday when a newer
stable Media3 is out (`node scripts/check-pins.mjs` says where it stands).

> **Note**: The [`files`](https://docs.npmjs.com/cli/v7/configuring-npm/package-json#files) array in `package.json` specifies which files get published. If you rename files/directories or add files elsewhere, you may need to update it.
