module QuizManagement
  extend ActiveSupport::Concern

  private

  def ensure_quiz_access
    redirect_to activities_path unless current_user.student?
  end

  def load_quiz_attempt
    @quiz_attempt = current_user.quiz_attempts.find_by(
      activity: @activity,
      id: session[:quiz_attempt_id]
    )
  end

  def clear_quiz_session
    session.delete(:quiz_attempt_id)
    session.delete(:last_quiz_score)
  end

  def load_questions
    if params[:skip_cache] == "true"
      @activity.questions.open_ended_last.to_a
    else
      Rails.cache.fetch(["activity_questions", @activity.id, @activity.updated_at.to_i], expires_in: 1.hour) do
        @activity.questions.open_ended_last.to_a
      end
    end
  end

  # As perguntas que o aluno responde no quiz. Na pílula, o desafio de escrita
  # fica de fora: ele é oferecido depois do resultado. A página da atividade e a
  # revisão de rascunho continuam usando load_questions, com a pergunta inteira.
  def quiz_questions
    challenge_id = @activity.writing_challenge&.id
    questions    = load_questions
    challenge_id ? questions.reject { |question| question.id == challenge_id } : questions
  end

  def load_completed_exercises
    session[:completed_quizzes] = current_user.quiz_attempts
                                              .select(:activity_id)
                                              .distinct
                                              .pluck(:activity_id)
  end
end 