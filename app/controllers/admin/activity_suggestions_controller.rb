class Admin::ActivitySuggestionsController < Admin::BaseController
  TEACHER_EMAIL = "daisy.oliani@gmail.com".freeze

  before_action :set_suggestion, only: [:approve, :reject]

  def index
    @suggestions = ActivitySuggestion.pending.order(created_at: :desc)
  end

  def approve
    generation = AiGeneration.create!(
      teacher:        teacher,
      kind:           "prompt",
      request_params: { prompt: build_prompt(@suggestion) }
    )
    AiActivityGenerationJob.perform_later(generation.id)
    @suggestion.update!(status: "approved")
    redirect_to generation_wait_activities_path(id: generation.id)
  end

  def reject
    @suggestion.update!(status: "rejected")
    redirect_to admin_activity_suggestions_path, notice: "Sugestão descartada."
  end

  def generate_now
    result = DailySuggestionAgentService.new(teacher: teacher).call
    if result[:skipped]
      redirect_to admin_activity_suggestions_path, notice: "Você já tem uma sugestão para hoje."
    elsif result[:success]
      redirect_to admin_activity_suggestions_path, notice: "Nova sugestão gerada!"
    else
      redirect_to admin_activity_suggestions_path, alert: "Erro ao gerar sugestão: #{result[:error]}"
    end
  end

  private

  def teacher
    @teacher ||= User.find_by(email: TEACHER_EMAIL)
  end

  def set_suggestion
    @suggestion = ActivitySuggestion.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_activity_suggestions_path, alert: "Sugestão não encontrada."
  end

  def build_prompt(suggestion)
    "Crie uma atividade de nível #{suggestion.level_hint} sobre o tema: #{suggestion.theme}. " \
    "Contexto da escolha: #{suggestion.rationale}"
  end
end
