class PushNotificationService
  VAPID = {
    subject:     "mailto:contato@practicebr.com",
    public_key:  ENV["VAPID_PUBLIC_KEY"],
    private_key: ENV["VAPID_PRIVATE_KEY"]
  }.freeze

  def self.send_to_user(user, title:, body:, url:)
    return unless ENV["VAPID_PUBLIC_KEY"].present?

    user.push_subscriptions.find_each do |sub|
      WebPush.payload_send(
        message:  { title: title, body: body, url: url }.to_json,
        endpoint: sub.endpoint,
        p256dh:   sub.p256dh_key,
        auth:     sub.auth_key,
        vapid:    VAPID
      )
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      sub.destroy
    rescue => e
      Rails.logger.error "[Push] Erro ao enviar · user ##{user.id}: #{e.message}"
    end
  end
end
