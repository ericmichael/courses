class CreateAccounts < ActiveRecord::Migration
  def change
    create_table "accounts", :force => true do |t|
      t.string   "name"
      t.string   "full_domain"
      t.timestamps
    end
  end
end
