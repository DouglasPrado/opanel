# frozen_string_literal: true

module Opanel
  module Gates
    # A JSON Schema validator covering exactly the keywords this repository's
    # schemas use — and refusing to run against a schema that uses any other.
    #
    # `config/pack/tasks.schema.json` was described as the contract and then not
    # applied: the checker hand-rolled a few of its rules and ignored the rest, so
    # a `status` of the wrong *type*, an `attempts` of -3, an unknown property, a
    # `commit` that is not a hash and a `diagnosis` under the declared minimum all
    # validated clean. A schema nobody executes is documentation.
    #
    # Deliberately not a gem: the schema uses eleven keywords, all of them
    # structural, and this is sixty lines. What a dependency would add is the
    # keywords we do not use — and the risk it would remove is covered by
    # `UnsupportedKeyword`, which refuses to validate against a constraint this
    # file cannot apply rather than skipping it silently. That is the failure mode
    # that mattered here.
    module JsonSchema
      class UnsupportedKeyword < StandardError; end

      Error = Struct.new(:pointer, :message, keyword_init: true) do
        def to_s = "#{pointer.to_s.empty? ? '(root)' : pointer} #{message}"
      end

      # Carry no constraint; safe to ignore.
      ANNOTATIONS = %w[$schema $id $comment title description default examples deprecated].freeze

      SUPPORTED = %w[
        type properties required additionalProperties enum pattern
        minLength maxLength minItems maxItems minimum maximum items
      ].freeze

      TYPES = {
        "object" => [ Hash ],
        "array" => [ Array ],
        "string" => [ String ],
        # `true.is_a?(Integer)` is false, so a boolean does not pass for a number.
        "integer" => [ Integer ],
        "number" => [ Numeric ],
        "boolean" => [ TrueClass, FalseClass ],
        "null" => [ NilClass ]
      }.freeze

      module_function

      def validate(schema, document)
        assert_supported!(schema)
        walk(schema, document, "", [])
      end

      # A schema keyword this validator does not implement is a constraint nobody
      # would apply. Loudly unsupported beats quietly ignored.
      def assert_supported!(schema)
        return unless schema.is_a?(Hash)

        unknown = schema.keys - ANNOTATIONS - SUPPORTED
        unless unknown.empty?
          raise UnsupportedKeyword,
            "the schema uses #{unknown.join(', ')}, which lib/gates/json_schema.rb does not " \
            "implement — implement it, or stop declaring a constraint nothing applies"
        end

        schema.fetch("properties", {}).each_value { |nested| assert_supported!(nested) }
        assert_supported!(schema["items"]) if schema.key?("items")
      end

      def walk(schema, value, pointer, errors)
        violation = type_violation(schema["type"], value)
        if violation
          errors << Error.new(pointer: pointer, message: violation)
          return errors
        end

        if schema["enum"] && !schema["enum"].include?(value)
          errors << Error.new(pointer: pointer,
            message: "is #{value.inspect}, not one of #{schema['enum'].join(', ')}")
        end

        case value
        when Hash then walk_object(schema, value, pointer, errors)
        when Array then walk_array(schema, value, pointer, errors)
        when String then walk_string(schema, value, pointer, errors)
        when Numeric then walk_number(schema, value, pointer, errors)
        end

        errors
      end

      def type_violation(expected, value)
        return nil if expected.nil?

        classes = TYPES.fetch(expected) { raise UnsupportedKeyword, "unknown type `#{expected}`" }
        return nil if classes.any? { |klass| value.instance_of?(klass) || value.is_a?(klass) }

        "should be #{expected} and is #{value.class.name.downcase}"
      end

      def walk_object(schema, value, pointer, errors)
        Array(schema["required"]).each do |key|
          next if value.key?(key)

          errors << Error.new(pointer: pointer, message: "is missing the required property `#{key}`")
        end

        properties = schema["properties"] || {}

        if schema["additionalProperties"] == false
          (value.keys - properties.keys).each do |key|
            errors << Error.new(pointer: pointer, message: "carries the unknown property `#{key}`")
          end
        end

        properties.each do |key, nested|
          walk(nested, value[key], "#{pointer}/#{key}", errors) if value.key?(key)
        end
      end

      def walk_array(schema, value, pointer, errors)
        if schema["minItems"] && value.length < schema["minItems"]
          errors << Error.new(pointer: pointer, message: "needs at least #{schema['minItems']} item(s)")
        end

        if schema["maxItems"] && value.length > schema["maxItems"]
          errors << Error.new(pointer: pointer, message: "allows at most #{schema['maxItems']} item(s)")
        end

        return unless schema["items"]

        value.each_with_index do |element, index|
          walk(schema["items"], element, "#{pointer}/#{index}", errors)
        end
      end

      def walk_string(schema, value, pointer, errors)
        if schema["pattern"] && !value.match?(Regexp.new(schema["pattern"]))
          errors << Error.new(pointer: pointer,
            message: "is #{value.inspect}, which does not match #{schema['pattern']}")
        end

        if schema["minLength"] && value.length < schema["minLength"]
          errors << Error.new(pointer: pointer,
            message: "is #{value.length} character(s); at least #{schema['minLength']} are required")
        end

        return unless schema["maxLength"] && value.length > schema["maxLength"]

        errors << Error.new(pointer: pointer,
          message: "is #{value.length} character(s); at most #{schema['maxLength']} are allowed")
      end

      def walk_number(schema, value, pointer, errors)
        if schema["minimum"] && value < schema["minimum"]
          errors << Error.new(pointer: pointer, message: "is #{value}, below the minimum #{schema['minimum']}")
        end

        return unless schema["maximum"] && value > schema["maximum"]

        errors << Error.new(pointer: pointer, message: "is #{value}, above the maximum #{schema['maximum']}")
      end
    end
  end
end
