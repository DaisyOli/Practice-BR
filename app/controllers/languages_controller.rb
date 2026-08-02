# O que se escolhe aqui é a língua dos EMAILS, não a do app.
#
# A interface é português para todo mundo, de propósito — ver o `switch_locale`
# do ApplicationController. O `language` do usuário é lido por um lugar só: os
# mailers, que carregam os três idiomas escritos na mão.
#
# Até 2026-08-02 a rota existia e nenhuma tela apontava para ela: quem nascesse
# com o idioma errado ficava preso nele para sempre. Foi o que aconteceu com as
# contas criadas antes de 31/07, que nasceram em inglês pelo default antigo da
# coluna — francófonos recebendo email em inglês, e a única saída era um UPDATE
# no banco (ver as migrações de 20260802). Agora a pessoa resolve sozinha.
class LanguagesController < ApplicationController
  # A confirmação sai na língua NOVA, não na antiga: quem acabou de escolher
  # francês lê a resposta em francês. É a prova imediata de que o botão fez o
  # que prometeu — e é o único lugar do app onde isso acontece.
  COPY = {
    "fr" => {
      ok:     "C'est noté : vous recevrez nos emails en français.",
      failed: "Impossible de changer la langue."
    },
    "en" => {
      ok:     "Got it — you'll receive our emails in English.",
      failed: "Could not change the language."
    },
    "pt" => {
      ok:     "Pronto! Você vai receber nossos emails em português.",
      failed: "Não foi possível alterar o idioma."
    }
  }.freeze

  def update
    new_language = params[:language].to_s

    unless User::LANGUAGES.include?(new_language)
      return redirect_back_with(:alert, copy_for(current_user.language)[:failed])
    end

    # `language_chosen_at` é o que separa escolha de herança. Só quem passa por
    # aqui escolheu — a landing e o default da coluna não escolhem por ninguém.
    # É o que autoriza a dashboard a mostrar inglês: em inglês, quem pediu.
    if current_user.update(language: new_language, language_chosen_at: Time.current)
      redirect_back_with(:notice, copy_for(new_language)[:ok])
    else
      Rails.logger.error "Failed to update user language: #{current_user.errors.full_messages.join(', ')}"
      redirect_back_with(:alert, copy_for(current_user.language)[:failed])
    end
  end

  private

  def copy_for(language)
    COPY.fetch(language.to_s, COPY["fr"])
  end

  # `allow_other_host: false` explícito: o destino vem do Referer, que é um
  # cabeçalho que o navegador manda e qualquer um pode forjar.
  def redirect_back_with(type, message)
    flash[type] = message
    redirect_back fallback_location: student_dashboard_path, allow_other_host: false
  end
end
