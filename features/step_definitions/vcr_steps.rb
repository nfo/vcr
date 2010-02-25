require 'tmpdir'

module VCRHelpers
  def have_expected_response(url, regex_str)
    simple_matcher("a response from #{url} that matches /#{regex_str}/") do |responses|
      regex = /#{regex_str}/i
      response = responses.detect { |r| URI.parse(r.uri) == URI.parse(url) }
      response.should_not be_nil
      response.response.body.should =~ regex
    end
  end
end
World(VCRHelpers)

Given /^we do not have a "([^\"]*)" sandbox$/ do |sandbox_name|
  fixture_file = File.join(VCR::Config.cache_dir, "#{sandbox_name}.yml")
  File.exist?(fixture_file).should be_false
end

Given /^we have a "([^\"]*)" file with (a|no) previously recorded response for "([^\"]*)"$/ do |file_name, a_or_no, url|
  fixture_file = File.join(VCR::Config.cache_dir, "#{file_name}.yml")
  File.exist?(fixture_file).should be_true
  responses = File.open(fixture_file, 'r') { |f| YAML.load(f.read) }
  should_method = a_or_no == 'a' ? :should : :should_not
  responses.map{ |r| URI.parse(r.uri) }.send(should_method, include(URI.parse(url)))
end

Given /^the "([^\"]*)" cache file has a response for "([^\"]*)" that matches \/(.+)\/$/ do |sandbox_name, url, regex_str|
  Given %{we have a "#{sandbox_name}" file with a previously recorded response for "#{url}"}
  Then %{the "#{sandbox_name}" cache file should have a response for "#{url}" that matches /#{regex_str}/}
end

Given /^this scenario is tagged with the vcr sandbox tag: "([^\"]+)"$/ do |tag|
  VCR.current_cucumber_scenario.should be_tagged_with(tag)
  VCR::CucumberTags.tags.should include(tag)
end

Given /^the previous scenario was tagged with the vcr sandbox tag: "([^\"]*)"$/ do |tag|
  last_scenario = VCR.completed_cucumber_scenarios.last
  last_scenario.should_not be_nil
  last_scenario.should be_tagged_with(tag)
  VCR::CucumberTags.tags.should include(tag)
end

When /^I make an HTTP get request to "([^\"]*)"$/ do |url|
  @http_requests ||= {}
  begin
    result = Net::HTTP.get_response(URI.parse(url))
  rescue => e
    result = e
  end
  @http_requests[url] = result
end

When /^I make (?:an )?HTTP get requests? to "([^\"]*)"(?: and "([^\"]*)")? within the "([^\"]*)" ?(#{VCR::Sandbox::VALID_RECORD_MODES.join('|')})? sandbox$/ do |url1, url2, sandbox_name, record_mode|
  record_mode ||= :unregistered
  record_mode = record_mode.to_sym
  urls = [url1, url2].select { |u| u.to_s.size > 0 }
  VCR.with_sandbox(sandbox_name, :record => record_mode) do
    urls.each do |url|
      When %{I make an HTTP get request to "#{url}"}
    end
  end
end

Then /^the "([^\"]*)" cache file should have a response for "([^\"]*)" that matches \/(.+)\/$/ do |sandbox_name, url, regex_str|
  yaml_file = File.join(VCR::Config.cache_dir, "#{sandbox_name}.yml")
  responses = File.open(yaml_file, 'r') { |f| YAML.load(f.read) }
  responses.should have_expected_response(url, regex_str)
end

Then /^I can test the scenario sandbox's recorded responses in the next scenario, after the sandbox has been destroyed$/ do
  # do nothing...
end

Then /^the HTTP get request to "([^\"]*)" should result in a fakeweb error$/ do |url|
  @http_requests[url].should be_instance_of(FakeWeb::NetConnectNotAllowedError)
end

Then /^the response for "([^\"]*)" should match \/(.+)\/$/ do |url, regex_str|
  regex = /#{regex_str}/i
  @http_requests[url].body.should =~ regex
end

Then /^there should not be a "([^\"]*)" cache file$/ do |sandbox_name|
  yaml_file = File.join(VCR::Config.cache_dir, "#{sandbox_name}.yml")
  File.exist?(yaml_file).should be_false
end