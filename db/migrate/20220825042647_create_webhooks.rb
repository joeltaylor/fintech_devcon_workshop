class CreateWebhooks < ActiveRecord::Migration[7.0]
  def change
    create_table :webhooks do |t|
      t.string :event_type
      t.json :data

      t.timestamps
    end
  end
end
