import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const workflow = readFileSync(new URL('../.github/workflows/ios-testflight.yml', import.meta.url), 'utf8');

/**
 * The upload step, and the reason it has a clock on it.
 *
 * `altool` retries a failing gateway by itself and does not stop. On run 56 it
 * sat against an App Store Connect answering HTML "Bad Gateway" for 72 minutes
 * and what ended it was the job timeout — long after the build had succeeded
 * and the .ipa was in the artifacts. These assertions are about the shape of
 * the guard rather than its wording, so the step cannot quietly lose it.
 */
test('the upload cannot outlive its own step', () => {
  const step = workflow.slice(workflow.indexOf('- name: Upload to TestFlight'));
  assert.match(step, /timeout-minutes: \d+/, 'the step has no ceiling of its own');

  const ceiling = Number(step.match(/timeout-minutes: (\d+)/)[1]);
  const job = Number(workflow.match(/runs-on: macos-15\s+timeout-minutes: (\d+)/)[1]);
  assert.ok(ceiling < job, `the step's ${ceiling} min must end before the job's ${job} min`);
});

test('each call to Apple is bounded, and a stuck one is killed', () => {
  assert.match(workflow, /run_bounded\(\)/, 'no watchdog: macOS has no timeout(1)');
  assert.match(workflow, /return 124/, 'the watchdog does not report a timeout distinguishably');
  assert.match(workflow, /kill -KILL/, 'a process that ignores TERM would still hang the step');
});

test('only a gateway failure is retried', () => {
  // Anything Apple says about this build is an answer. Repeating the question
  // wastes a macOS runner and tells nobody anything new.
  assert.match(workflow, /gateway_failure\(\)/);
  assert.match(workflow, /if ! gateway_failure "\$log"; then/);
  assert.match(workflow, /a retry would be refused the same way/);
});

test('a build Apple already has is not reported as a failure', () => {
  // The gateway can break *after* the upload was accepted, and the retry then
  // fails for the opposite reason.
  assert.match(workflow, /already_there\(\)/);
  assert.match(workflow, /ITMS-4238/);
});

test('the failure message says where the build is', () => {
  // The .ipa is kept before the upload runs, so a failed upload never costs
  // the build — the message has to say so, or somebody re-runs the whole
  // thing for nothing.
  const kept = workflow.indexOf('- name: Keep the .ipa');
  const upload = workflow.indexOf('- name: Upload to TestFlight');
  assert.ok(kept > 0 && kept < upload, 'the .ipa must be kept before the upload is attempted');
  assert.match(workflow, /artifacts and can be uploaded later without rebuilding/);
});
