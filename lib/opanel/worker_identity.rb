# frozen_string_literal: true

module Opanel
  # Worker identity: a unique identifier for the process executing an Operation.
  #
  # The identity is derived from the process, never accepted from a caller (AC10).
  # Workers use this to claim and renew leases on resources.
  #
  # Format: "hostname-pid-boot_id" to uniquely identify a process across crashes
  # and restarts. The boot_id is a monotonic counter set at process startup.
  #
  # Stored in the configuration (environment variable) so it persists across
  # multiple Solid Queue worker spawn/exit cycles within the same process.
  class WorkerIdentity
    def self.current
      @current ||= ENV["OPANEL_WORKER_IDENTITY"] || generate
    end

    # Generates a new worker identity based on hostname, PID, and a startup clock.
    # This runs once at boot and is stored in the environment for the lifetime
    # of the process, so all workers spawned under this process share an identity.
    def self.generate
      hostname = Socket.gethostname.slice(0, 32)
      pid = Process.pid
      # A simple boot counter to distinguish restarts. In production, the orchestrator
      # assigns a node/pod identity; in development/test, this is sufficient.
      boot_id = ENV["OPANEL_WORKER_BOOT_ID"] || "0"

      "#{hostname}-#{pid}-#{boot_id}".slice(0, 255)
    end

    private_class_method :generate
  end
end
