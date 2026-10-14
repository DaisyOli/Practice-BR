# A lista de atividades de um nível que a professora manda para os alunos —
# por WhatsApp (botão "Copiar") ou em PDF (o navegador salva a página, preparada
# para impressão, sem biblioteca nova no app).
#
# A ordem é a do percurso do nível (Admin › Percurso): primeiro as atividades do
# caminho, na ordem escolhida; depois todas as outras, agrupadas pelo tema que o
# agente propôs e a Daisy confirmou. Existe porque as professoras não davam
# conta de procurar e saber o que sugerir aos alunos.
class ActivityListsController < ApplicationController
  before_action :require_teacher!

  NO_THEME = "Outros temas".freeze

  def show
    @level = params[:level].presence_in(User::CEFR_LEVELS) || "A1"
    scope  = Activity.published.where(level: @level)

    @path     = scope.in_path.to_a
    rest      = scope.where(path_position: nil).order(:title).to_a
    @by_theme = rest.group_by { |a| a.theme.presence || NO_THEME }
                    .sort_by { |theme, _| [theme == NO_THEME ? 1 : 0, theme] }
    @counts   = Activity.published.group(:level).count
  end

  private

  def require_teacher!
    redirect_to root_path, alert: "Acesso restrito a professores." unless current_user&.teacher?
  end
end
