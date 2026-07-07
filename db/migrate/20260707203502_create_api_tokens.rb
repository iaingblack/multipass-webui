class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.string :id_slug, null: false
      t.string :name, null: false
      t.string :prefix, null: false
      t.string :sha256_digest, null: false
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :api_tokens, :id_slug, unique: true
    add_index :api_tokens, :name, unique: true
    add_index :api_tokens, :sha256_digest, unique: true
  end
end
