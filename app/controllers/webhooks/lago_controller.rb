require 'openssl'
require 'jwt'

class Webhooks::LagoController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    if queue_valid_event
      head :ok
    else
      head :bad_request
    end
  end

  private

  def queue_valid_event
    payload = request.body.read

    decoded_signature = JWT.decode(
      request.headers['X-Lago-Signature'],
      OpenSSL::PKey::RSA.new(Base64.decode64(PayToWait.lago_public_key)),
      true,
      {
        algorithm: 'RS256',
        iss: ENV['LAGO_URL'],
        verify_iss: true,
      },
    ).first

    return false unless decoded_signature['data'] == payload
    webhook = Webhook.create(event_type: params['webhook_type'], data: JSON.parse(payload))
    LagoWebhookJob.perform_later(webhook.id)
  end
end
