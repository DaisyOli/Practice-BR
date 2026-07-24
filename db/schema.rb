# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_07_24_083400) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "level"
    t.bigint "teacher_id", null: false
    t.string "media_url"
    t.text "explanation_text"
    t.text "statement"
    t.string "slug"
    t.string "video_url"
    t.boolean "draft", default: false, null: false
    t.boolean "ai_generated"
    t.datetime "published_at"
    t.boolean "explanation_is_transcript"
    t.string "unsplash_cover_url"
    t.string "unsplash_cover_credit"
    t.index ["slug"], name: "index_activities_on_slug", unique: true
    t.index ["teacher_id"], name: "index_activities_on_teacher_id"
  end

  create_table "activity_ratings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "activity_id", null: false
    t.integer "stars", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_activity_ratings_on_activity_id"
    t.index ["user_id", "activity_id"], name: "index_activity_ratings_on_user_id_and_activity_id", unique: true
    t.index ["user_id"], name: "index_activity_ratings_on_user_id"
    t.check_constraint "stars >= 1 AND stars <= 5", name: "stars_range_check"
  end

  create_table "activity_suggestions", force: :cascade do |t|
    t.string "title"
    t.string "theme"
    t.string "level_hint"
    t.string "status", default: "pending", null: false
    t.integer "activity_id"
    t.integer "teacher_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "rationale"
  end

  create_table "ai_generations", force: :cascade do |t|
    t.bigint "teacher_id", null: false
    t.bigint "activity_id"
    t.string "kind", null: false
    t.string "status", default: "queued", null: false
    t.jsonb "request_params", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_ai_generations_on_activity_id"
    t.index ["teacher_id"], name: "index_ai_generations_on_teacher_id"
  end

  create_table "column_matchings", force: :cascade do |t|
    t.bigint "activity_id", null: false
    t.string "title"
    t.string "instruction"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_column_matchings_on_activity_id"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.uuid "locked_by_id"
    t.datetime "locked_at"
    t.integer "lock_type", limit: 2
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["created_at"], name: "index_good_jobs_on_created_at"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_on_discarded", order: :desc, where: "((finished_at IS NOT NULL) AND (error IS NOT NULL))"
    t.index ["id"], name: "index_good_jobs_on_unfinished_or_errored", where: "((finished_at IS NULL) OR (error IS NOT NULL))"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_for_candidate_dequeue_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_on_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at", "id"], name: "index_good_jobs_on_queue_name_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["queue_name"], name: "index_good_jobs_on_queue_name"
    t.index ["scheduled_at", "queue_name"], name: "index_good_jobs_on_scheduled_at_and_queue_name"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "matching_pairs", force: :cascade do |t|
    t.bigint "column_matching_id", null: false
    t.string "left_item"
    t.string "right_item"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["column_matching_id"], name: "index_matching_pairs_on_column_matching_id"
  end

  create_table "paragraph_orderings", force: :cascade do |t|
    t.bigint "activity_id", null: false
    t.string "title"
    t.text "instruction"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "paragraph_sentences_count"
    t.index ["activity_id"], name: "index_paragraph_orderings_on_activity_id"
  end

  create_table "paragraph_sentences", force: :cascade do |t|
    t.bigint "paragraph_ordering_id", null: false
    t.text "sentence", null: false
    t.integer "correct_position", null: false
    t.integer "display_position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["paragraph_ordering_id", "correct_position"], name: "index_paragraph_sentences_on_ordering_and_position", unique: true
    t.index ["paragraph_ordering_id"], name: "index_paragraph_sentences_on_paragraph_ordering_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "endpoint", null: false
    t.string "p256dh_key", null: false
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "endpoint"], name: "index_push_subscriptions_on_user_id_and_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "questions", force: :cascade do |t|
    t.string "content"
    t.string "question_type"
    t.bigint "activity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "options"
    t.string "correct_answer"
    t.text "evaluation_prompt"
    t.integer "weight", default: 1, null: false
    t.jsonb "correct_answers", default: []
    t.index ["activity_id"], name: "index_questions_on_activity_id"
  end

  create_table "quiz_attempts", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "activity_id", null: false
    t.float "score"
    t.jsonb "results"
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "teacher_comments"
    t.datetime "started_at"
    t.index ["activity_id"], name: "index_quiz_attempts_on_activity_id"
    t.index ["user_id"], name: "index_quiz_attempts_on_user_id"
  end

  create_table "sentence_orderings", force: :cascade do |t|
    t.bigint "activity_id", null: false
    t.text "sentence"
    t.text "instruction"
    t.integer "display_order"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sentence_words_count"
    t.index ["activity_id"], name: "index_sentence_orderings_on_activity_id"
  end

  create_table "sentence_words", force: :cascade do |t|
    t.bigint "sentence_ordering_id", null: false
    t.string "word"
    t.integer "correct_position"
    t.integer "display_position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sentence_ordering_id"], name: "index_sentence_words_on_sentence_ordering_id"
  end

  create_table "suggestions", force: :cascade do |t|
    t.text "content"
    t.integer "position"
    t.bigint "activity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_suggestions_on_activity_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", default: "trial"
    t.string "language", default: "en"
    t.string "invitation_token"
    t.datetime "invitation_created_at"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.integer "invitation_limit"
    t.string "invited_by_type"
    t.bigint "invited_by_id"
    t.integer "invitations_count", default: 0
    t.boolean "admin"
    t.string "name"
    t.string "level"
    t.integer "trial_activities_used"
    t.datetime "trial_expires_at"
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.string "subscription_status"
    t.datetime "subscription_current_period_end"
    t.string "professional_type"
    t.boolean "weekly_reminder_email"
    t.integer "daily_quiz_count", default: 0, null: false
    t.date "daily_quiz_date"
    t.datetime "trial_reminder_sent_at"
    t.datetime "inactivity_nudge_sent_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["language"], name: "index_users_on_language"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "users", column: "teacher_id"
  add_foreign_key "activity_ratings", "activities"
  add_foreign_key "activity_ratings", "users"
  add_foreign_key "ai_generations", "activities"
  add_foreign_key "ai_generations", "users", column: "teacher_id"
  add_foreign_key "column_matchings", "activities"
  add_foreign_key "matching_pairs", "column_matchings"
  add_foreign_key "paragraph_orderings", "activities"
  add_foreign_key "paragraph_sentences", "paragraph_orderings"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "questions", "activities"
  add_foreign_key "quiz_attempts", "activities"
  add_foreign_key "quiz_attempts", "users"
  add_foreign_key "sentence_orderings", "activities"
  add_foreign_key "sentence_words", "sentence_orderings"
  add_foreign_key "suggestions", "activities"
end
