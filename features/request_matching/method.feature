Feature: Matching on Method

  Use the `:method` request matcher to match requests on the HTTP method
  (i.e. GET, POST, PUT, DELETE, etc).  You will generally want to use
  this matcher.

  The `:method` matcher is used (along with the `:uri` matcher) by default
  if you do not specify how requests should match.

  Background:
    Given a previously recorded cassette file "cassettes/example.yml" with:
      """
      --- 
      - !ruby/struct:VCR::HTTPInteraction 
        request: !ruby/struct:VCR::Request 
          method: :post
          uri: http://post-request.com:80/
          body: 
          headers: 
        response: !ruby/struct:VCR::Response 
          status: !ruby/struct:VCR::ResponseStatus 
            code: 200
            message: OK
          headers: 
            content-length: 
            - "13"
          body: post response
          http_version: "1.1"
      - !ruby/struct:VCR::HTTPInteraction 
        request: !ruby/struct:VCR::Request 
          method: :get
          uri: http://get-request.com:80/
          body:
          headers: 
        response: !ruby/struct:VCR::Response 
          status: !ruby/struct:VCR::ResponseStatus 
            code: 200
            message: OK
          headers: 
            content-length: 
            - "12"
          body: get response
          http_version: "1.1"
      """

  Scenario Outline: Replay interaction that matches the HTTP method
    And a file named "method_matching.rb" with:
      """ruby
      require 'vcr_cucumber_helpers'
      include_http_adapter_for("<http_lib>")

      require 'vcr'

      VCR.configure do |c|
        c.stub_with <stub_with>
        c.cassette_library_dir = 'cassettes'
      end

      VCR.use_cassette('example', :match_requests_on => [:method]) do
        puts "Response for GET: " + response_body_for(:get, "http://example.com/")
      end

      VCR.use_cassette('example', :match_requests_on => [:method]) do
        puts "Response for POST: " + response_body_for(:post,  "http://example.com/")
      end
      """
    When I run `ruby method_matching.rb`
    Then it should pass with:
      """
      Response for GET: get response
      Response for POST: post response
      """

    Examples:
      | stub_with  | http_lib        |
      | :fakeweb   | net/http        |
      | :webmock   | net/http        |
      | :webmock   | httpclient      |
      | :webmock   | patron          |
      | :webmock   | curb            |
      | :webmock   | em-http-request |
      | :webmock   | typhoeus        |
      | :typhoeus  | typhoeus        |
      | :excon     | excon           |

