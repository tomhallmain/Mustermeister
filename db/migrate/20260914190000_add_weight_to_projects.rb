class AddWeightToProjects < ActiveRecord::Migration[8.0]
  # Nullable on purpose: left blank, a project's weight follows its
  # default_priority, so the common case needs no decision from the user and
  # existing projects keep the relative standing they already had. A value
  # here pins the weight independently of what new tasks start at.
  def change
    add_column :projects, :weight, :string
  end
end
