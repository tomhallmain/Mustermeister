class AddTranslateTargetLanguageToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :translate_target_language, :string
  end
end
