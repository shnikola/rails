# frozen_string_literal: true

require "active_support/core_ext/object/duplicable"

module ActiveSupport
  # +ParameterFilter+ allows you to specify keys for sensitive data from
  # hash-like object and replace corresponding value. Filtering only certain
  # sub-keys from a hash is possible by using the dot notation:
  # 'credit_card.number'. If a proc is given, each key and value of a hash and
  # all sub-hashes are passed to it, where the value or the key can be replaced
  # using String#replace or similar methods.
  #
  #   ActiveSupport::ParameterFilter.new([:password])
  #   => replaces the value to all keys matching /password/i with "[FILTERED]"
  #
  #   ActiveSupport::ParameterFilter.new([:foo, "bar"])
  #   => replaces the value to all keys matching /foo|bar/i with "[FILTERED]"
  #
  #   ActiveSupport::ParameterFilter.new([/\Apin\z/i, /\Apin_/i])
  #   => replaces the value for the exact (case-insensitive) key 'pin' and all
  #   (case-insensitive) keys beginning with 'pin_', with "[FILTERED]".
  #   Does not match keys with 'pin' as a substring, such as 'shipping_id'.
  #
  #   ActiveSupport::ParameterFilter.new(["credit_card.code"])
  #   => replaces { credit_card: {code: "xxxx"} } with "[FILTERED]", does not
  #   change { file: { code: "xxxx"} }
  #
  #   ActiveSupport::ParameterFilter.new([-> (k, v) do
  #     v.reverse! if /secret/i.match?(k)
  #   end])
  #   => reverses the value to all keys matching /secret/i
  class ParameterFilter
    FILTERED = "[FILTERED]" # :nodoc:

    # Create instance with given filters. Supported type of filters are +String+, +Regexp+, and +Proc+.
    # Other types of filters are treated as +String+ using +to_s+.
    # For +Proc+ filters, key, value, and optional original hash is passed to block arguments.
    #
    # ==== Options
    #
    # * <tt>:mask</tt> - A replaced object when filtered. Defaults to <tt>"[FILTERED]"</tt>.
    def initialize(filters = [], mask: FILTERED)
      @mask = mask
      compile_filters!(filters)
    end

    # Mask value of +params+ if key matches one of filters.
    def filter(params)
      @no_filters ? params.dup : call(params)
    end

    # Returns filtered value for given key. For +Proc+ filters, third block argument is not populated.
    def filter_param(key, value)
      @no_filters ? value : value_for_key(key, value)
    end

  private
    def compile_filters!(filters)
      @no_filters = filters.empty?
      return if @no_filters

      @regexps, strings = [], []
      @deep_regexps, deep_strings = nil, nil
      @blocks = nil

      filters.each do |item|
        case item
        when Proc
          (@blocks ||= []) << item
        when Regexp
          if item.to_s.include?("\\.")
            (@deep_regexps ||= []) << item
          else
            @regexps << item
          end
        else
          s = Regexp.escape(item.to_s)
          if s.include?("\\.")
            (deep_strings ||= []) << s
          else
            strings << s
          end
        end
      end

      @regexps << Regexp.new(strings.join("|"), true) unless strings.empty?
      (@deep_regexps ||= []) << Regexp.new(deep_strings.join("|"), true) if deep_strings
    end

    def call(params, full_parent_key = nil, original_params = params)
      filtered_params = params.class.new

      params.each do |key, value|
        filtered_params[key] = value_for_key(key, value, full_parent_key, original_params)
      end

      filtered_params
    end

    def value_for_key(key, value, full_parent_key = nil, original_params = nil)
      if @deep_regexps
        full_key = full_parent_key ? "#{full_parent_key}.#{key}" : key.to_s
      end

      if @regexps.any? { |r| r.match?(key.to_s) }
        value = @mask
      elsif @deep_regexps&.any? { |r| r.match?(full_key) }
        value = @mask
      elsif value.is_a?(Hash)
        value = call(value, full_key, original_params)
      elsif value.is_a?(Array)
        value = value.map { |v| value_for_key(key, v, full_parent_key, original_params) }
      elsif @blocks
        key = key.dup if key.duplicable?
        value = value.dup if value.duplicable?
        @blocks.each { |b| b.arity == 2 ? b.call(key, value) : b.call(key, value, original_params) }
      end

      value
    end
  end
end
