class AddQuietAlertSentAtToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :quiet_alert_sent_at, :datetime
  end
end
