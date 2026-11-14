# Tellomi client UI tests

XCUITest coverage for the untested client backlog (`backlog.csv`, 928 rows). The tests drive the real Tellomi app. They do not change it.

## What a row can be

| Status | Meaning |
| --- | --- |
| `pass` / `fail` | A simulator test saw that row's element and checked it. |
| `blocked` | The row needs a screen, a server error, or a logged-in session this run did not reach. |
| `device_only` | Push, camera, microphone, Siri, Face ID, or a call. The manifest marks these and no shard runs them. |

One test reports many ids. The id lists are the `Coverage` arrays in `Sources/Coverage.swift`. `tools/test_tellomi_ui_results.py` checks that every backlog id is exactly one of those three, and that device-only rows are not also covered.

## Login

`TELLOMI_TEST_PHONE_A` and `TELLOMI_TEST_PHONE_B` are optional GitHub secrets. When either is empty, the shard uses this suite's dedicated numbers: A `9996617090`, B `9996617091`. Other parallel testers use `7001`–`7089`, so this suite does not. A number outside `99966170xx` is refused and no code is sent.

The production server does not use the dev SMS code `12345`. That code is only the `none` provider (`teamgram-server` README: production does not accept it). `pkg/phonenumber/test_phone.go` still answers `99966XYYYY` before Aliyun, including on production (`auth.sendCode` `finishSendCode`). The code is the digit after `99966`, repeated five times.

`99966170xx` is that range with datacenter digit `1`, so the code is `11111`. `TELLOMI_TEST_CODE` overrides it when the secret is set. Leave it unset for this range.

`12345` is rejected for these numbers (`AcceptsTestCode("9996612345", "12345")` is false in the server tests).

The tests do not pass `--ui-test`. That flag isolates the database and also sets `testingEnvironment`, and the handshake then asks for datacenter id + 10000 (`MTDatacenterAuthInnerDataDatacenterId`). The production server does not complete that handshake. Each test is wiped with `simctl uninstall` instead.

Logged-out tests run either way. With the dedicated numbers, login, settings, Discover, and the composer sign in. Account B reaches the code screen and does not own backlog ids. A refused number does not.

AI compose switches are not toggled. The composer test only checks that the default-off entry labels are absent.

## How CI runs them

`.github/workflows/tellomi-ui-tests.yml` builds the unsigned simulator app once (`release_sim_arm64`, no App Store signing), then five jobs compile only this test bundle against that `.app` and run one shard each. `tools/merge_results.py` writes `ui-results.json`.

Locally, on a Mac with the simulator app already built:

```sh
python3 Tellomi/UITests/tools/test_tellomi_ui_results.py
bash Tellomi/UITests/tools/run_shard.sh 1 /path/to/Telegram.app /tmp/tellomi-ui-shard
```

`//Tellomi/UITests:TellomiClientUITests` is the Bazel `ios_ui_test` for the same sources. It is `manual`. The workflow does not call `bazel test` for it, because that would rebuild the app on every shard.

Regenerate the Xcode project after adding a Swift file:

```sh
python3 Tellomi/UITests/tools/generate_xcodeproj.py
```
