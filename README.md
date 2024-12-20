<img src="/Nautik Helper/Assets.xcassets/AppIcon.appiconset/app_icon_helper_256.png" align="right" width="128" height="128" />

# Nautik Helper

<!-- [![CI](https://github.com/nautik-io/helper/actions/workflows/ci.yml/badge.svg)](https://github.com/nautik-io/helper/actions/workflows/ci.yml)
[![Release](https://github.com/nautik-io/helper/actions/workflows/release.yml/badge.svg)](https://github.com/nautik-io/helper/actions/workflows/release.yml) -->

Helper app to bridge Nautik's compatibility with the full kubeconfig spec, including exec plugins, without having the main app exit the sandbox.

This exists because kubeconfig auth scenarios are diverse and a lot of setups (including the standard kubeconfig files exported out of of GCP, AWS, Azure and DigitalOcean) rely on calling executables in a user's PATH for ephemeral Kubernetes credential issuing. Calling arbitrary executables isn't possible as a sandboxed Mac app, but exiting the sandbox just to call local executables would prevent us from distributing the app via the Mac App Store. So all things exec are happening in this helper app that can optionally be used by people whose auth scenarios aren't implemented in the main app and can also easily be audited, since the whole exec thing might be suspicious to some people. Additionally, there's support for token and certificate files. Credential data is shared between the helper app and the main app using the system keychain.

If you can prevent using this, don't use it and try using the auth scenarios implemented in the main app instead, as they will work better across platforms without having to have a Mac running just to refresh credentials.

## How the helper app works

The helper app allows you to add kubeconfig files to keep track of via a file picker UI. The file paths of tracked kubeconfig files are stored on the [`UserDefaults`](https://developer.apple.com/documentation/foundation/userdefaults) in a serialized array of paths under the key `kubeconfigs`. Every valid cluster on the tracked kubeconfig files can be added to (or removed from) the keychain with a checkbox UI on the helper app's settings.

<img width="385" alt="The Nautik Helper app's main window, showing two Kubernetes clusters under management." src="https://github.com/nautik-io/helper/assets/19625431/550627e2-e380-4789-af89-a56f1f09e2cc">

Clusters on the keychain are reevaluated by the helper app every 30 seconds. If a cluster's corresponding kubeconfig entry includes `client-certificate`, `client-key` or `token-file` keys, the file contents of the corresponding files are copied into the `client-certificate-data`, `client-key-data` and `token` fields of the stored cluster to have them be consumed by the main app on macOS, iOS or iPadOS. If a cluster's corresponding kubeconfig entry includes an `exec` value, the helper app spawns a process as the user running the helper app, executing the corresponding exec-based authentication plugin and copying its output into the `client-certificate-data`, `client-key-data` and `token` fields of the stored cluster to have them be consumed by the main app.

<img width="472" alt="The Nautik Helper app's cluster settings window, showing two kubeconfig files with one Kubernetes cluster inside of each." src="https://github.com/nautik-io/helper/assets/19625431/698b8691-5eb1-4b4c-b86b-8bc36da28e43">

Support for the `auth-provider` field on the kubeconfig is currently unimplemented. But support for the `oidc` auth provider is planned to be included on the main app at a later point. Contributions to the helper app extending the range of supported auth methods are very welcome.

To allow to be run on multiple Macs and user accounts in parallel without interference, the helper app stores the device UUID and user of the system it was added on with the cluster.

## Installation

Head to the [latest release](https://github.com/nautik-io/helper/releases/latest) page and grab the latest app build from the attachment named `helper-<version>.zip`. The `.zip` file contains an `.app` bundle that has the hardened runtime enabled and is notarized with Apple, so it can be securely opened without bypassing macOS Gatekeeper. We're currently doing the notarization on our dev machines; transparent CI automation for it will follow as soon as GitHub supports macOS 14 action runners.

## Updates

We rely on [AppUpdater](https://github.com/mxcl/AppUpdater) and GitHub releases for a super simple update process. The app should automatically check for updates and silently update itself once a day. Alternatively, you have a menu option on the app to manually check for updates.

## About Nautik

Nautik is an accessible, concurrent Kubernetes client that is native to Apple platforms. Our mission is to build the best possible Kubernetes UX for the Apple ecosystem. You can get Nautik [on the App Store](https://apps.apple.com/app/apple-store/id1672838783?pt=126097015&ct=GitHub&mt=8).
