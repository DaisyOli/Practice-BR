class Admin::DraftsController < Admin::BaseController
  TEACHER_EMAIL = "daisy.oliani@gmail.com".freeze

  def index
    @teacher   = User.find_by(email: TEACHER_EMAIL)
    @goals     = ContentTarget.goals
    @generated = generated_by_level
    @drafts    = Activity.where(ai_generated: true, draft: true)
                         .order(created_at: :desc)
                         .includes(:questions, :sentence_orderings, :paragraph_orderings, :column_matchings)
  end

  def generate
    teacher = User.find_by(email: TEACHER_EMAIL)
    return redirect_to admin_drafts_path, alert: "Professora não encontrada." unless teacher

    level = requested_level || level_furthest_from_goal
    return redirect_to admin_drafts_path, notice: "Meta atingida em todos os níveis! 🎉" if level.nil?

    # A geração roda em background (sem limite de 30s do Heroku e sem
    # gerações simultâneas disputando slug); o admin espera no modal do agente.
    generation = AiGeneration.create!(
      teacher:        teacher,
      kind:           "agent",
      request_params: { level: level }
    )
    AiActivityGenerationJob.perform_later(generation.id)

    redirect_to generation_wait_activities_path(id: generation.id)
  end

  def update_targets
    ContentTarget.transaction do
      target_params.each do |level, goal|
        ContentTarget.find_or_initialize_by(level: level).update!(goal: goal.presence)
      end
    end

    redirect_to admin_drafts_path, notice: "Metas atualizadas."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_drafts_path, alert: "Meta inválida: #{e.record.errors.full_messages.to_sentence}"
  end

  def destroy
    activity = Activity.find(params[:id])
    title = activity.title
    activity.destroy
    redirect_to admin_drafts_path, notice: "Rascunho '#{title}' descartado."
  end

  private

  # A lista de níveis válidos vem do enum do Activity — a fonte de verdade — e
  # não da tabela de metas. Assim um nível sem meta continua escolhível na mão,
  # e um nível novo não some em silêncio: era essa confusão que mantinha o C1
  # fora do ar sem nenhum aviso.
  def requested_level
    params[:level].to_s.presence_in(Activity.levels.keys)
  end

  # Nível com a maior distância até a própria meta. Níveis sem meta ficam de
  # fora: o automático não tem como saber quanto conteúdo eles deveriam ter.
  # Devolve nil quando não falta nada em lugar nenhum.
  def level_furthest_from_goal
    current = generated_by_level

    ContentTarget.goals
                 .filter_map { |level, goal| [level, goal - current.fetch(level, 0)] if goal }
                 .select     { |_, gap| gap.positive? }
                 .max_by     { |_, gap| gap }
                 &.first
  end

  # Conta rascunhos junto das publicadas: um rascunho já é conteúdo daquele
  # nível esperando revisão, e contá-lo evita empilhar dez rascunhos do mesmo
  # nível. Uma conta só, usada pela tela e pela decisão, para que a barra de
  # progresso mostre exatamente o número que o agente usou para decidir.
  def generated_by_level
    Activity.where(ai_generated: true).group(:level).count
  end

  def target_params
    params.fetch(:goals, {}).permit(*Activity.levels.keys).to_h
  end
end
