# Contributing

Maintained by [WhoaStudio](https://github.com/WhoaStudio) (@WhoaStudio).
Please follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Setup and verification

Clone the repository and open `whoa-type.xcodeproj` in Xcode. Use macOS 26.5+
and Swift tools 6.2+ with the macOS SDK. No third-party runtime dependencies
or external services are required.

```sh
xcodebuild -project whoa-type.xcodeproj -scheme whoa-type -destination 'platform=macOS' build
swift test
```

See [README](README.md) for permissions and manual testing, and
[validation](Docs/VALIDATION.md) for release checks. Never commit signing
credentials, personal Xcode settings, or generated build artifacts.

## Branch and pull request flow

Fork the repository, branch from `stable`, and create a focused branch such as
`fix/short-description` or `feature/short-description`. Open pull requests against
**stable**. Explain the problem, changes, and relevant verification; include
screenshots for visible changes. Keep changes small and follow existing conventions.
Address review feedback and let a maintainer merge after CI and one approval.

Report bugs and propose features using the issue forms. Report vulnerabilities
privately using [SECURITY.md](SECURITY.md).

Contributions to source and documentation use the [MIT license](LICENSE).
Bundled audio has separate licensing restrictions; do not add recordings without
clear provenance and redistribution permission.
