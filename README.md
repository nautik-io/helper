<img src="/Nautik Helper/Assets.xcassets/AppIcon.appiconset/app_icon_helper_1024.png" align="right" width="128" height="128" />

# Nautik Helper

Helper app to bridge Nautik's compatibility with the full kubeconfig spec, including exec plugins, without having the main app exit the sandbox.

This exists because kubeconfig auth scenarios are diverse and a lot of setups (including the standard kubeconfig files exported out of of GCP, AWS, Azure and DigitalOcean) rely on calling executables in a user's PATH for ephemeral Kubernetes credential issuing. Calling arbitrary executables isn't possible as a sandboxed Mac app, but exiting the sandbox just to call local executables would prevent us from distributing the app via the Mac App Store. So all things exec are happening in this helper app that can optionally be used by people whose auth scenarios aren't implemented in the main app and also can easily be audited, since the whole exec thing might be suspicious to some people. Credential data is shared between the helper app and the main app using the system keychain.

If you can prevent using this, don't use it and try to use the auth scenarios implemented in the main app instead, as they will work better across platforms without having to have a Mac running just to refresh credentials.

## Installation

Head to the [latest release](https://github.com/nautik-io/helper/releases/latest) page and grab the latest app image.

## Updates

We rely on [AppUpdater](https://github.com/mxcl/AppUpdater) and GitHub releases for a super simple update process. The app should automatically check for updates and silently update itself once a day. Alternatively, you have a menu option on the app to manually check for updates.

## About Nautik

Nautik is an accessible, concurrent Kubernetes client that is native to Apple platforms. Our mission is to build the best possible Kubernetes UX for the Apple ecosystem. Our app is currently in beta, with a first stable release expected this winter. To join our TestFlight, visit [our website](https://nautik.io) and sign up.
