# A tela que tira a voz das IAs de dentro do código.
#
# Herda o `require_admin!` do Admin::BaseController, e isso basta: esta tela é
# mais perigosa que a de rascunhos — quem edita daqui muda como a IA fala com
# TODOS os alunos, na hora seguinte, sem deploy e sem revisão de ninguém.
class Admin::AiPromptsController < Admin::BaseController
  before_action :load_prompt, except: :index

  def index
    # Agrupado por IA, na ordem em que o registro declara: o agente de conteúdo
    # primeiro (é o mais mexido), a correção depois, a sugestão por último.
    @groups = AiPrompt.registry.group_by { |_key, entry| entry[:group] }
    @saved  = AiPrompt.where(key: AiPrompt.keys).index_by(&:key)
  end

  def edit
    @body     = AiPrompt.body_for(@key)
    @default  = AiPrompt.default_for(@key)
    @versions = @record&.versions&.limit(10) || []
  end

  def update
    @record ||= AiPrompt.new(key: @key)
    @record.body = params.require(:ai_prompt)[:body].to_s

    if @record.save
      redirect_to admin_ai_prompts_path, notice: "#{entry[:label]}: texto salvo. A próxima chamada da IA já usa ele."
    else
      # Devolve o texto que ela escreveu, e não o salvo — perder uma reescrita
      # longa por causa de um erro de validação seria cruel.
      @body     = @record.body
      @default  = AiPrompt.default_for(@key)
      @versions = @record.persisted? ? @record.versions.limit(10) : []
      flash.now[:alert] = @record.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  # Voltar ao texto de fábrica = apagar a linha. O chão do `body_for` faz o
  # resto. Não existe "restaurar" que precise copiar texto de volta.
  def destroy
    @record&.destroy
    redirect_to admin_ai_prompts_path, notice: "#{entry[:label]}: voltou ao texto original do código."
  end

  def restore
    version = @record.versions.find(params[:version_id])

    if @record.update(body: version.body)
      redirect_to edit_admin_ai_prompt_path(@key), notice: "Versão de #{l(version.created_at, format: :short)} restaurada."
    else
      redirect_to edit_admin_ai_prompt_path(@key), alert: @record.errors.full_messages.to_sentence
    end
  end

  private

  def load_prompt
    @key = params[:key].to_s
    return redirect_to admin_ai_prompts_path, alert: "Prompt desconhecido." unless AiPrompt.keys.include?(@key)

    @record = AiPrompt.find_by(key: @key)
  end

  def entry = AiPrompt.entry(@key)
  helper_method :entry
end
