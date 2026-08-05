# CI Exit Code Cheatsheet

Reference for diagnosing `xcodebuild` and GitHub Actions failures in this repo.
Each entry includes what the code means, what actually caused it here, and the fix.

## xcodebuild exit codes

| Code | Meaning | Seen in this repo | Fix |
|---|---|---|---|
| **0** | Success — everything passed | Goal state | N/A |
| **1** | Generic failure, usually something before tests even ran | `xcodegen generate` couldn't find a source file at the path listed in `project.yml` | Check the exact path in the error against what's actually in the repo — casing and folder structure must match exactly |
| **65** | Build succeeded, but one or more tests failed | `testConnectionSearchShowsPatientWaitingState` failed — a timing assumption (1.5s) was too short for real CI simulator boot overhead (~5s) | Increase the delay/timeout so it safely outlasts realistic CI overhead, not just local expectations |
| **66** | Project or scheme not found | `-project YourApp.xcodeproj` — a placeholder name with no matching file in the repo (used for genres without a real app yet) | Only affects `ios-tests.yml`; each genre needs a real `project.yml` + `Sources/` folder like DemoApp has, or the workflow stays disabled |

## Common annotation messages (not exit codes, but frequent noise)

| Message | Meaning | Action needed? |
|---|---|---|
| `No files were found with the provided path: ...xcresult` | The result bundle was never created because an earlier step failed | No — this is a symptom, not the cause. Suppressed here via `if-no-files-found: ignore` |
| `Node.js 20 is deprecated...` | GitHub's runner infrastructure notice, unrelated to this repo's code | No — safe to ignore |
| `The following taps are not trusted: aws/tap` | Default Homebrew warning baked into GitHub's macOS runner image | No — unrelated to this project |
| `Using the first of multiple matching destinations` | Informational — multiple simulator architectures matched the same device UDID | No — harmless, expected |

## Where to look when something fails

1. **Actions tab → the failed run → the job → the specific step with a red X** (not the top-level annotations box, which only shows a filtered summary)
2. Scroll to the **bottom** of that step's expanded log — the real error is usually the last 10-20 lines
3. Cross-reference the exit code against this table before assuming it's a new, unrelated problem

## Adding new entries

When a new failure type shows up: add a row here with the exact cause and fix once resolved, so the same issue never needs re-diagnosing from scratch.
