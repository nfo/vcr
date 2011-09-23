require 'fileutils'
require 'erb'
require 'set'

require 'vcr/cassette/reader'
require 'vcr/cassette/http_interaction_list'

module VCR
  class Cassette
    VALID_RECORD_MODES = [:all, :none, :new_episodes, :once]

    attr_reader :name, :record_mode, :match_requests_on, :erb, :re_record_interval, :tag, :http_interactions

    def initialize(name, options = {})
      options = VCR.configuration.default_cassette_options.merge(options)
      invalid_options = options.keys - [
        :record,
        :erb,
        :match_requests_on,
        :re_record_interval,
        :tag,
        :update_content_length_header
      ]

      if invalid_options.size > 0
        raise ArgumentError.new("You passed the following invalid options to VCR::Cassette.new: #{invalid_options.inspect}.")
      end

      @name               = name
      @record_mode        = options[:record]
      @erb                = options[:erb]
      @match_requests_on  = options[:match_requests_on]
      @re_record_interval = options[:re_record_interval]
      @tag                = options[:tag]
      @record_mode        = :all if should_re_record?
      @update_content_length_header = options[:update_content_length_header]

      raise_error_unless_valid_record_mode

      set_http_connections_allowed
      load_recorded_interactions
    end

    def eject
      write_recorded_interactions_to_disk
      restore_http_connections_allowed
    end

    def recorded_interactions
      @recorded_interactions ||= []
    end

    def record_http_interaction(interaction)
      new_recorded_interactions << interaction
    end

    def new_recorded_interactions
      @new_recorded_interactions ||= []
    end

    def file
      File.join(VCR.configuration.cassette_library_dir, "#{sanitized_name}.yml") if VCR.configuration.cassette_library_dir
    end

    def update_content_length_header?
      @update_content_length_header
    end

    private

    def sanitized_name
      name.to_s.gsub(/[^\w\-\/]+/, '_')
    end

    def raise_error_unless_valid_record_mode
      unless VALID_RECORD_MODES.include?(record_mode)
        raise ArgumentError.new("#{record_mode} is not a valid cassette record mode.  Valid modes are: #{VALID_RECORD_MODES.inspect}")
      end
    end

    def should_re_record?
      @re_record_interval &&
      File.exist?(file) &&
      File.stat(file).mtime + @re_record_interval < Time.now &&
      InternetConnection.available?
    end

    def should_allow_http_connections?
      case record_mode
        when :none; false
        when :once; file.nil? || !File.size?(file)
        else true
      end
    end

    def should_stub_requests?
      record_mode != :all
    end

    def should_remove_matching_existing_interactions?
      record_mode == :all
    end

    def set_http_connections_allowed
      @orig_http_connections_allowed = VCR.http_stubbing_adapter.http_connections_allowed?
      VCR.http_stubbing_adapter.http_connections_allowed = should_allow_http_connections?
    end

    def restore_http_connections_allowed
      VCR.http_stubbing_adapter.http_connections_allowed = @orig_http_connections_allowed
    end

    def load_recorded_interactions
      if file && File.size?(file)
        interactions = VCR::YAML.load(raw_yaml_content)

        invoke_hook(:before_playback, interactions)

        interactions.reject! do |i|
          i.request.uri.is_a?(String) && VCR.configuration.uri_should_be_ignored?(i.request.uri)
        end

        if update_content_length_header?
          interactions.each { |i| i.response.update_content_length_header }
        end

        recorded_interactions.replace(interactions)
      end

      interactions = should_stub_requests? ? recorded_interactions : []
      @http_interactions = HTTPInteractionList.new(interactions, match_requests_on, VCR.http_interactions)
    end

    def raw_yaml_content
      VCR::Cassette::Reader.new(file, erb).read
    end

    def merged_interactions
      old_interactions = recorded_interactions

      if should_remove_matching_existing_interactions?
        match_attributes = match_requests_on

        new_request_matchers = Set.new new_recorded_interactions.map do |i|
          i.request.matcher(match_attributes)
        end

        old_interactions = old_interactions.reject do |i|
          new_request_matchers.include?(i.request.matcher(match_attributes))
        end
      end

      old_interactions + new_recorded_interactions
    end

    def write_recorded_interactions_to_disk
      return unless VCR.configuration.cassette_library_dir
      return if new_recorded_interactions.empty?

      interactions = merged_interactions
      invoke_hook(:before_record, interactions)
      return if interactions.empty?

      directory = File.dirname(file)
      FileUtils.mkdir_p directory unless File.exist?(directory)
      File.open(file, 'w') { |f| f.write VCR::YAML.dump(interactions) }
    end

    def invoke_hook(type, interactions)
      interactions.delete_if do |i|
        VCR.configuration.invoke_hook(type, tag, i, self)
        i.ignored?
      end
    end
  end
end
