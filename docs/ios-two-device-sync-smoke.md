# iOS Two-Device Sync Smoke Matrix

Use two signed-in iOS devices under the same dealer.

Before each run:
- Open `Account -> Data Health` on both devices.
- Run `Run Diagnostics`.
- Copy or share the report from both devices.
- Confirm both devices show the same dealer id.
- Confirm queue is empty before starting a clean scenario.

## Scenario 1: Create on device A, receive on device B

1. On device A, create a new vehicle with a unique VIN.
2. Wait for sync or bring device B to foreground.
3. On device B, open Vehicles and pull to refresh if needed.

Expected:
- Vehicle appears on device B.
- `Data Health` on both devices stays `Healthy` or briefly `Degraded`.
- Queue returns to `0`.

## Scenario 2: Update on device A, receive on device B

1. On device A, edit an existing vehicle price or notes.
2. Bring device B to foreground.
3. Verify updated fields.

Expected:
- Latest values appear on device B.
- No dead letters.

## Scenario 3: Delete on device A, remove on device B

1. On device A, delete a vehicle, expense, or client.
2. Bring device B to foreground and refresh.

Expected:
- Deleted record disappears on device B.
- Record does not reappear after another refresh.

## Scenario 4: Offline create on device A

1. Put device A into Airplane Mode.
2. Create a new record on device A.
3. Open `Data Health` on device A.

Expected while offline:
- Record exists locally on device A.
- Queue count increases.
- Health becomes `Degraded`, not `Blocked`.

Then:
1. Disable Airplane Mode on device A.
2. Wait a few seconds or foreground the app.
3. Bring device B to foreground.

Expected after reconnect:
- Queue drains automatically.
- Record appears on device B.
- Health returns to `Healthy`.

## Scenario 5: Offline delete on device A

1. Put device A offline.
2. Delete a record on device A.
3. Reconnect device A.
4. Bring device B to foreground.

Expected:
- Delete is queued while offline.
- Delete propagates after reconnect.
- Record does not resurrect on either device.

## Scenario 6: Conflict edit/edit

1. Choose one shared record.
2. On device A, edit field X but do not foreground device B yet.
3. On device B, edit the same field to a different value.
4. Bring both devices online and foreground them.

Expected:
- Both devices converge to one final value.
- No endless flip-flop between values.
- `Data Health` must not end in `Blocked`.

## Scenario 7: Conflict edit/delete

1. On device A, edit a record.
2. On device B, delete the same record.
3. Bring both devices online and foreground them.

Expected:
- Both devices converge to the same final state.
- Record is either deleted everywhere or restored nowhere unexpectedly.
- No dead-letter queue items.

## Scenario 8: Cold start recovery

1. Force-quit the app on both devices.
2. Reopen device A first, then device B.
3. Run `Data Health` on both.

Expected:
- Last sync metadata is still present.
- Queue state survives restart correctly.
- No corrupted queue behavior.

## Failure triage

If a scenario fails, collect from both devices:
- `Data Health` report text
- exact record id or VIN
- which device performed the write first
- whether the device was offline, backgrounded, or foregrounded
- whether queue count, next retry, or dead letters changed
