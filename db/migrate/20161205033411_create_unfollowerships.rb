class CreateUnfollowerships < ActiveRecord::Migration
  def change
    create_table :unfollowerships, id: false do |t|
      t.integer :follower_id,           index: true, null: false
      t.integer :from_uid,    limit: 8, index: true, null: false
    end
    add_index :unfollowerships, %i(from_uid follower_id), unique: true
  end
end
