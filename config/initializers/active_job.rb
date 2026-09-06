# Job arguments are persisted in PostgreSQL and read back by a worker. Anything
# Active Job can deserialize is therefore reachable from stored data.
#
# Rails ships a serializer that turns a Module or Class argument into its name and
# constantizes it on the way back. Opanel has no job that needs to pass a class
# around, so the serializer is removed: a payload naming an arbitrary constant now
# fails at enqueue time instead of resolving at execution time (Annex C §16).
#
# Removing it narrows the payload vocabulary to primitives, symbols, times,
# durations, ranges, big decimals and GlobalIDs — all inert.
Rails.application.config.to_prepare do
  ActiveJob::Serializers.serializers =
    ActiveJob::Serializers.serializers.reject do |serializer|
      serializer.is_a?(ActiveJob::Serializers::ModuleSerializer)
    end
end
