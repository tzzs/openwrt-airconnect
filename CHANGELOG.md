# Changelog

## [0.2.0](https://github.com/tzzs/openwrt-airconnect/compare/v0.1.0...v0.2.0) (2026-10-26)


### Features

* **dev:** add mock-backed preview of the production view ([d4dc8fb](https://github.com/tzzs/openwrt-airconnect/commit/d4dc8fb061ea70f17e7defaa8eda74130630fa8c))
* **luci:** add Chinese translation and Pages repository ([f128ca1](https://github.com/tzzs/openwrt-airconnect/commit/f128ca1a5cdbd69e007ec7cbc9d3ec2a774310dd))
* **luci:** add scoped shadcn-inspired stylesheet ([894cd38](https://github.com/tzzs/openwrt-airconnect/commit/894cd38b679e77579b97e4f7b22dac0c3d38f08f))
* **luci:** add shared field validation rules for the manager view ([77a380d](https://github.com/tzzs/openwrt-airconnect/commit/77a380df5803191ca17d295429c21c839ea7aba2))
* **luci:** add speakers, settings and diagnostics view ([e57fabc](https://github.com/tzzs/openwrt-airconnect/commit/e57fabccf67d211e80b1cffcce8fa7e2521d69eb))
* **luci:** offer the advanced engine parameters per engine ([c949c9c](https://github.com/tzzs/openwrt-airconnect/commit/c949c9c7861a0fb634fb6b030e195894c64bf9bd))
* **luci:** register page, permission split and package recipe ([c56900c](https://github.com/tzzs/openwrt-airconnect/commit/c56900c04072c43cf766dbc22d4a7fbadd3c9631))
* **luci:** render broadcasting as a measurement, playback as unknown ([90d36ca](https://github.com/tzzs/openwrt-airconnect/commit/90d36cab6e0e968fb3aee91adb7cc0ccb56e3ce8))
* **luci:** warn when two speakers share an AirPlay name ([c8b769f](https://github.com/tzzs/openwrt-airconnect/commit/c8b769f3a4b575599d4378e2e53fc6f1b2d1f39b))
* **manager:** add a dry-run-first legacy migration script ([a058dea](https://github.com/tzzs/openwrt-airconnect/commit/a058deaf8c801ecd95c93c5bff2b4021b94e7324))
* **manager:** add bounded SSDP discovery parser ([cf33dcf](https://github.com/tzzs/openwrt-airconnect/commit/cf33dcf8d2cc6f445dc03b8742ee276378ab2594))
* **manager:** add package recipe, default UCI config and conffiles ([7c7181f](https://github.com/tzzs/openwrt-airconnect/commit/7c7181fbf1f2744430e53f0313c2a3b33ae30d97))
* **manager:** add pure config validation and XML renderer ([294a79e](https://github.com/tzzs/openwrt-airconnect/commit/294a79e0f0536d4fbacd15c36d22773507d09edb))
* **manager:** add pure state and bounded file modules for the RPC backend ([88ba619](https://github.com/tzzs/openwrt-airconnect/commit/88ba61922d52ea3104b02229842380fa5145c2a1))
* **manager:** add runtime.uc UCI adapter with atomic XML writes ([38f74bb](https://github.com/tzzs/openwrt-airconnect/commit/38f74bbbf899e8ddbaa1a6d0456c611890e7811e))
* **manager:** add the airconnect.manager rpcd ucode backend ([821e8f2](https://github.com/tzzs/openwrt-airconnect/commit/821e8f28531f3690d1c611a3bfb4b2e309691881))
* **manager:** install runtime.uc as an executable ([6bb85d6](https://github.com/tzzs/openwrt-airconnect/commit/6bb85d6e75399b4909f8115ac60cd565ae26ee16))
* **manager:** model the remaining upstream engine parameters ([d3500d0](https://github.com/tzzs/openwrt-airconnect/commit/d3500d0d135339ed5aeb4796ec6f38f85fa70ef3))
* **manager:** observe the AirPlay advertisement over mDNS ([1ac7d1c](https://github.com/tzzs/openwrt-airconnect/commit/1ac7d1ce23c84107e123f7d09e5328de552a0d79))
* **manager:** report broadcasting separately from running and playback ([73a4e73](https://github.com/tzzs/openwrt-airconnect/commit/73a4e7306d32ba03bc3733ef9df24994fcd3468b))
* **manager:** ship the advanced options in the default configuration ([2110f02](https://github.com/tzzs/openwrt-airconnect/commit/2110f0279fbb0ea57983b332e7121190b3cc3abe))


### Bug Fixes

* **build:** stop the SDK build from silently dropping a package and building kmods ([9281e76](https://github.com/tzzs/openwrt-airconnect/commit/9281e768596302e2807f3330f41ae0a6c89a4bf6))
* **ci:** expose ucode runtime library ([b08bb91](https://github.com/tzzs/openwrt-airconnect/commit/b08bb919a58b04d56ad802d8b962a12a071eb33b))
* **ci:** finish release automation documentation ([81121c4](https://github.com/tzzs/openwrt-airconnect/commit/81121c4604aa2eac7f4382cf65fb71e87b14aeca))
* **ci:** isolate release write permissions ([89c9d81](https://github.com/tzzs/openwrt-airconnect/commit/89c9d8156b373104ca1ab6358552e2689d9f9ff5))
* **ci:** run host tests on the interpreter the suites require ([c958b30](https://github.com/tzzs/openwrt-airconnect/commit/c958b303c4b7a2242e39f8ba77a74f29d8ef1571))
* **ci:** scope release workflow permissions ([dd520aa](https://github.com/tzzs/openwrt-airconnect/commit/dd520aa76f3298fa95477616dfd0f3091119aecc))
* **config:** make anchored patterns reject trailing newline and control bytes ([6bb8d2f](https://github.com/tzzs/openwrt-airconnect/commit/6bb8d2f1378e2acef4ebdcf6f209a3240d2665c8))
* **discovery:** scan bytes for control characters instead of NUL bracket class ([4a48e20](https://github.com/tzzs/openwrt-airconnect/commit/4a48e2026abca8107717e3f266ac9c5540aee4b8))
* **engine:** gate the ARCH check on a non-empty ARCH and verify the binaries in a script ([18bfede](https://github.com/tzzs/openwrt-airconnect/commit/18bfede61240707123775fc67908ef77175b5388))
* **engine:** normalize ARCH to upstream name and self-diagnose extraction ([0c5abbe](https://github.com/tzzs/openwrt-airconnect/commit/0c5abbec47e2f9299c89768b30824dc78df9ff79))
* **luci:** make the package visible to the SDK package scanner ([5687042](https://github.com/tzzs/openwrt-airconnect/commit/5687042cd93ae8b6ff1a9489cb0a6faf4ee64da4))
* **luci:** render each duplicate AirPlay name on its own line ([b0821d3](https://github.com/tzzs/openwrt-airconnect/commit/b0821d3dcbfcfc5fa5176b34daacb3ae5e1513ef))
* **luci:** validate form fields with the shared backend rules ([b9e1aff](https://github.com/tzzs/openwrt-airconnect/commit/b9e1affbb003244c89379777cdac20a29f1db2cd))
* **manager:** align interface validation with the backend allowlist ([bd2d840](https://github.com/tzzs/openwrt-airconnect/commit/bd2d840661d4e106cb074a3a5b151337424c376e))
* **manager:** align the init script interface check with the backend ([8694030](https://github.com/tzzs/openwrt-airconnect/commit/869403097c1c2393cd1c8997e16c74c8f882ddf9))
* **manager:** keep the migrated file's mode and report it in the dry run ([4a803c1](https://github.com/tzzs/openwrt-airconnect/commit/4a803c18e58d30f5bd3cd76d4b61be39896e5e2c))
* **manager:** use the module syntax the target's ucode actually accepts ([fb4aef4](https://github.com/tzzs/openwrt-airconnect/commit/fb4aef4d26ff88b96677ec0274c9191a61d8b124))
* **migrate:** name the legacy keys the migration cannot carry over ([3047529](https://github.com/tzzs/openwrt-airconnect/commit/3047529b23b1d39e3b95dd128c5a35af17be9f97))
* **migration:** read the legacy section name instead of assuming 'main' ([ed1213e](https://github.com/tzzs/openwrt-airconnect/commit/ed1213e4f6603e07a36bb1297108fe2e0bcd9716))
* **package:** the opt-in is the UCI option, not enabling the init script ([158337e](https://github.com/tzzs/openwrt-airconnect/commit/158337ee2760058d4ec3aa62492f5ce16cb37d46))


### Refactoring

* **manager:** drop the unused dropPartialLine export ([1303ea3](https://github.com/tzzs/openwrt-airconnect/commit/1303ea39c39e44f16db1dca0be3e89d45e131aab))
