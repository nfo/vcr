require 'webmock'

module VCR
  module HttpStubbingAdapters
    module WebMock
      include VCR::HttpStubbingAdapters::Common
      extend self

      MIN_PATCH_LEVEL   = '1.7.0'
      MAX_MINOR_VERSION = '1.7'

      def vcr_request_from(webmock_request)
        VCR::Request.new(
          webmock_request.method,
          webmock_request.uri.to_s,
          webmock_request.body,
          webmock_request.headers
        )
      end

    private

      def version
        ::WebMock.version
      end

      def response_hash_for(response)
        {
          :body    => response.body,
          :status  => [response.status.code.to_i, response.status.message],
          :headers => response.headers
        }
      end

      def normalize_uri(uri)
        ::WebMock::Util::URI.normalize_uri(uri).to_s
      end

      GLOBAL_VCR_HOOK = ::WebMock::RequestStub.new(:any, /.*/).tap do |stub|
        stub.with { |request|
          vcr_request = vcr_request_from(request)

          if uri_should_be_ignored?(request.uri)
            false
          elsif VCR.http_interactions.has_interaction_matching?(vcr_request)
            true
          elsif http_connections_allowed?
            false
          else
            raise_connections_disabled_error(vcr_request)
          end
        }.to_return(lambda { |request|
          response_hash_for VCR.http_interactions.response_for(vcr_request_from(request))
        })
      end

      ::WebMock::StubRegistry.instance.register_request_stub(GLOBAL_VCR_HOOK)
      ::WebMock.allow_net_connect!
    end
  end
end

WebMock.after_request(:real_requests_only => true) do |request, response|
  if VCR::HttpStubbingAdapters::WebMock.enabled?
    http_interaction = VCR::HTTPInteraction.new(
      VCR::HttpStubbingAdapters::WebMock.vcr_request_from(request),
      VCR::Response.new(
        VCR::ResponseStatus.new(
          response.status.first,
          response.status.last
        ),
        response.headers,
        response.body,
        '1.1'
      )
    )

    VCR.record_http_interaction(http_interaction)
  end
end

WebMock::NetConnectNotAllowedError.class_eval do
  undef stubbing_instructions
  def stubbing_instructions(*args)
    '.  ' + VCR::HttpStubbingAdapters::Common::RECORDING_INSTRUCTIONS
  end
end

WebMock::StubRegistry.class_eval do
  undef reset!
  def reset!
    self.request_stubs = [VCR::HttpStubbingAdapters::WebMock::GLOBAL_VCR_HOOK]
  end
end

