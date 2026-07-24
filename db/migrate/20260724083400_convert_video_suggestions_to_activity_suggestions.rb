class ConvertVideoSuggestionsToActivitySuggestions < ActiveRecord::Migration[7.1]
  def change
    rename_table :video_suggestions, :activity_suggestions
    rename_column :activity_suggestions, :topic, :theme
    remove_column :activity_suggestions, :youtube_url, :string
    remove_column :activity_suggestions, :thumbnail_url, :string
    remove_column :activity_suggestions, :channel_name, :string
    remove_column :activity_suggestions, :transcript, :text
    remove_column :activity_suggestions, :search_query, :string
    add_column :activity_suggestions, :rationale, :text
  end
end
