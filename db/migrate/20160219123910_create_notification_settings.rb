class CreateNotificationSettings < ActiveRecord::Migration
  def change
    create_table :notification_settings do |t|
      t.boolean :email,                  null: false, default: true
      t.boolean :dm,                     null: false, default: true
      t.boolean :news,                   null: false, default: true
      t.boolean :search,                 null: false, default: true
      t.boolean :prompt_report,          null: false, default: true

      t.datetime :last_email_at,         null: true
      t.datetime :last_dm_at,            null: true
      t.datetime :last_news_at,          null: true
      t.datetime :search_sent_at,        null: true
      t.datetime :prompt_report_sent_at, null: true
      t.integer :from_id,                null: false

      t.timestamps null: false
    end
    add_index :notification_settings, :from_id
  end
end
