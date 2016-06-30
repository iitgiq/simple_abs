class CreateAbTest < ActiveRecord::Migration
  def self.up
    create_table :ab_tests, :force => true do |t|
      t.text     "experiment"
      t.string   "choice"
      t.integer  "impression", :default => 0
      t.integer  "conversion",  :default => 0

      t.timestamps
    end
  end

  def self.down
    drop_table :ab_tests
  end
end