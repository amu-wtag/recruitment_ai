class CreateCandidates < ActiveRecord::Migration[8.0]
  def change
    create_table :candidates do |t|
      t.string :name
      t.string :github_username
      t.jsonb :skills
      t.integer :experience
      t.integer :github_score
      t.integer :total_score

      t.timestamps
    end
  end
end
