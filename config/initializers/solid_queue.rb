# Solid Queue process-liveness tuning.
#
# A worker that dies mid-execution leaves its claimed job behind. Another
# supervisor only reclaims it after the dead process misses its heartbeat window,
# so these two values decide how long a crashed job waits before it runs again.
#
# The defaults are the gem's production-safe ones. They are overridable so the
# integration test that kills a worker can observe the reclaim without waiting five
# minutes — the mechanism under test is the same either way.
SolidQueue.process_heartbeat_interval =
  Float(ENV.fetch("OPANEL_JOB_HEARTBEAT_INTERVAL_SECONDS", 60)).seconds

SolidQueue.process_alive_threshold =
  Float(ENV.fetch("OPANEL_JOB_ALIVE_THRESHOLD_SECONDS", 300)).seconds

# Keep finished jobs so a failed run can still be inspected; the recurring task in
# config/recurring.yml clears them.
SolidQueue.preserve_finished_jobs = true
