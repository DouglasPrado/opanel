# Starts and stops real Solid Queue worker processes.
#
# A job that only ever runs inline has never met the transport it will run on in
# production. The crash behaviour in particular — what happens to a job whose
# worker disappears — cannot be observed without a process to kill.
module SolidQueueWorker
  class Timeout < StandardError; end

  # Spawns the supervisor in its own process group so the whole tree can be
  # killed the way an OOM kill or a node failure would kill it.
  def start_worker(env = {})
    pid = Process.spawn(
      {
        "RAILS_ENV" => "test",
        "OPANEL_JOB_HEARTBEAT_INTERVAL_SECONDS" => "1",
        "OPANEL_JOB_ALIVE_THRESHOLD_SECONDS" => "2"
      }.merge(env),
      Gem.ruby, Rails.root.join("bin/jobs").to_s,
      chdir: Rails.root.to_s,
      pgroup: true,
      out: File::NULL,
      err: File::NULL
    )

    running_workers << pid
    pid
  end

  # SIGKILL to the whole group: no shutdown hook runs, nothing is released
  # cleanly. That is the point.
  def kill_worker(pid, signal: "KILL")
    Process.kill(signal, -Process.getpgid(pid))
    Process.wait(pid)
    running_workers.delete(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    running_workers.delete(pid)
  end

  def stop_all_workers
    running_workers.dup.each { |pid| kill_worker(pid, signal: "TERM") }
  end

  def running_workers
    @running_workers ||= []
  end

  # Polls a condition instead of sleeping a guessed interval, so the test is slow
  # only when the system is slow, and fails with a description rather than with a
  # bare timeout.
  def wait_until(description, timeout: 20, interval: 0.2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      result = yield
      return result if result

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise Timeout, "timed out after #{timeout}s waiting for: #{description}"
      end

      sleep interval
    end
  end
end

RSpec.configure do |config|
  config.include SolidQueueWorker, :solid_queue_worker
  config.after(:each, :solid_queue_worker) { stop_all_workers }
end
