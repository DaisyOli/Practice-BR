class QuizAttempt < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :activity
  
  validates :score, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :results, presence: true
  
  # Definir quais campos resultados deve ter
  validates_each :results do |record, attr, value|
    unless value.is_a?(Hash) && value.key?("score") && value.key?("total_questions")
      record.errors.add(attr, "deve conter score e total_questions")
    end
  end
  
  scope :completed, -> { where.not(submitted_at: nil) }
  scope :for_user, ->(user) { where(user: user) }

  PASSING_SCORE = 60

  # Teto do texto do desafio de escrita da pílula: 2 a 5 frases cabem com
  # folga, e o teto protege a correção por IA de um texto colado sem fim.
  CHALLENGE_MAX_CHARS = 3000

  before_create :set_submitted_at
  after_create  :increment_trial_counter
  after_create  :increment_daily_counter
  after_commit  :clear_user_attempts_cache, if: :user_id?

  def total_correct
    results["total_correct"] if results
  end
  
  def total_questions
    results["total_questions"] if results
  end
  
  def correct_percentage
    score || 0
  end

  def passed?
    score.to_i >= PASSING_SCORE
  end
  
  def question_results
    results["results"] if results
  end

  def open_ended_results
    return [] unless results&.dig("results").is_a?(Hash)
    results["results"].select { |_k, v| v.is_a?(Hash) && v["question_type"] == "open_ended" }
  end

  # true enquanto houver resposta aberta aguardando correção do AiGradingJob
  def ai_grading_pending?
    return false unless results&.dig("results").is_a?(Hash)
    results["results"].values.any? { |v| v.is_a?(Hash) && v["ai_pending"] }
  end

  # A nota ainda vai mudar? Só se a IA estiver corrigindo uma aberta DO QUIZ. O
  # desafio de escrita da pílula é corrigido à parte e não mexe na nota.
  def score_pending_ai?
    return false unless results&.dig("results").is_a?(Hash)
    results["results"].values.any? { |v| v.is_a?(Hash) && v["ai_pending"] && !v["challenge"] }
  end

  # O desafio de escrita da pílula (ver Activity#writing_challenge), guardado
  # como resposta aberta da tentativa, com a marca "challenge".
  def challenge_results
    return {} unless results&.dig("results").is_a?(Hash)
    results["results"].select { |_k, v| v.is_a?(Hash) && v["challenge"] }
  end

  def challenge_entry
    challenge_results.values.first
  end

  def teacher_comment_for(question_id)
    (teacher_comments || {})["question_#{question_id}"].presence
  end

  def normalized_results(questions = {})
    data = results.dup

    unless data.key?("total_questions")
      if data.values.any? { |v| v.is_a?(Hash) && v["is_correct"] }
        data = {
          "activity_id" => activity_id,
          "results"     => data,
          "score"       => score,
          "total_correct"   => data.values.count { |r| r["is_correct"] },
          "total_questions" => data.size,
          "submitted_at"    => submitted_at
        }
      else
        data = {
          "activity_id"     => activity_id,
          "results"         => {},
          "score"           => score.to_i,
          "total_correct"   => 0,
          "total_questions" => 0,
          "submitted_at"    => submitted_at || Time.current
        }
      end
    end

    data["results"] = {} unless data["results"].is_a?(Hash)

    data["results"].each do |question_id, result|
      question = questions[question_id.to_i]
      if question
        result["question_text"]   ||= question.content
        result["question_type"]   ||= question.question_type
        result["correct_answer"]  ||= question.correct_answer
      end
      result["given_answer"] ||= I18n.t('quiz.not_answered')
    end

    data
  end
  
  # Método para limpar tentativas anônimas antigas (pode ser executado por um job)
  def self.clean_anonymous_attempts(older_than = 1.day)
    where(user_id: nil).where('created_at < ?', older_than.ago).delete_all
  end
  
  private
  
  def set_submitted_at
    self.submitted_at ||= Time.current
  end

  def increment_trial_counter
    user&.trial? && user.increment!(:trial_activities_used)
  end

  def increment_daily_counter
    user&.increment_daily_count!
  end
  
  def clear_user_attempts_cache
    Rails.cache.delete_matched("best_attempts/#{user_id}*")
  end
end
