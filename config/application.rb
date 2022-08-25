require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module PayToWait
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end

  def self.lago_client
    @lago_client ||= ::Lago::Api::Client.new(api_key: ENV['LAGO_API_KEY'], api_url: ENV['LAGO_URL'])
  end

  def self.lago_public_key
    return @webhooks_public_key if defined?(@webhooks_public_key)

    require 'net/http'

    uri = URI("#{ENV['LAGO_URL']}/api/v1/webhooks/public_key")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == "https"

    response = http.send_request(
      'GET',
      uri.request_uri,
      '',
      { 'Authorization' => "Bearer #{ENV['LAGO_API_KEY']}" }
    )

    @webhooks_public_key = response.body
  end
end
