require 'spec_helper'

describe VCR::HttpStubbingAdapters::Faraday do
  it_behaves_like 'an http stubbing adapter',
    %w[ faraday-typhoeus faraday-net_http faraday-patron ],
    :status_message_not_exposed, :does_not_support_rotating_responses

  it_performs('version checking',
    :valid    => %w[ 0.6.0 0.6.10 ],
    :too_low  => %w[ 0.5.9 0.4.99 ],
    :too_high => %w[ 0.7.0 1.0.0 ]
  ) do
    before(:each) { @orig_version = Faraday::VERSION }
    after(:each)  { Faraday::VERSION = @orig_version }

    # Cannot be regular method def as that raises a "dynamic constant assignment" error
    define_method :stub_version do |version|
      ::Faraday::VERSION = version
    end
  end
end
