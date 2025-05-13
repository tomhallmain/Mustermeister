class InitialSchema < ActiveRecord::Migration[8.0]
  def change
    # Create Users first as it's referenced by other tables
    create_table :users do |t|
      t.string :name
      t.string :email

      t.timestamps
    end
    add_index :users, :email, unique: true

    # Create Projects which belong to users
    create_table :projects do |t|
      t.string :title
      t.text :description
      t.datetime :due_date
      t.references :user, null: false, foreign_key: true
      t.datetime :last_activity_at

      t.timestamps
    end

    # Create Tasks which belong to projects and users
    create_table :tasks do |t|
      t.string :title
      t.text :description
      t.boolean :completed, default: false
      t.datetime :due_date
      t.string :priority, default: 'medium'
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    # Create Tags
    create_table :tags do |t|
      t.string :name

      t.timestamps
    end
    add_index :tags, :name, unique: true

    # Create the Tasks-Tags join table
    create_join_table :tasks, :tags do |t|
      t.index [:task_id, :tag_id]
      t.index [:tag_id, :task_id]
    end

    # Create Comments which belong to tasks and users
    create_table :comments do |t|
      t.text :content
      t.references :user, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: true

      t.timestamps
    end
  end
end
