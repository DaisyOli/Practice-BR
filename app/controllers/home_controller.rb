class HomeController < ApplicationController
  # A política de privacidade precisa ser legível por quem ainda não tem conta
  # (o RGPD exige informar *antes* da coleta) — então ela fica fora tanto do
  # login quanto do redirecionamento de trial.
  skip_before_action :authenticate_user!, only: :privacy
  skip_before_action :check_trial_restrictions!, only: :privacy

  # Três versões, e não são traduções uma da outra: a francesa e a inglesa seguem
  # o RGPD (a Practice-BR é operada da França, quem audita é a CNIL), a portuguesa
  # segue a LGPD (ANPD, prazo de 15 dias, direito de revisão do art. 20, criança
  # menor de 12). O francês é o fallback por causa do estabelecimento.
  PRIVACY_LANGS = %w[fr en pt].freeze

  def index
  end

  def trial_expired
  end

  def privacy
    @privacy_lang = requested_privacy_lang
    # O conteúdo muda conforme o Accept-Language, então proxies e CDNs precisam
    # saber que não podem servir a mesma cópia pra todo mundo.
    response.headers["Vary"] = "Accept-Language"
  end

  private

  # Ordem de decisão: o que a pessoa escolheu no seletor > o idioma do navegador
  # dela > francês.
  def requested_privacy_lang
    return params[:lang] if PRIVACY_LANGS.include?(params[:lang])

    browser_privacy_lang || PRIVACY_LANGS.first
  end

  # "fr-FR,fr;q=0.9,en-US;q=0.8" → primeiro idioma da lista que a gente publica,
  # respeitando a ordem de preferência (o q=) declarada pelo navegador.
  def browser_privacy_lang
    request.env["HTTP_ACCEPT_LANGUAGE"].to_s
           .split(",")
           .map do |part|
             tag, quality = part.split(";q=")
             [tag.to_s.strip.downcase[0, 2], (quality || "1").to_f]
           end
           .sort_by { |_, quality| -quality }
           .map(&:first)
           .find { |code| PRIVACY_LANGS.include?(code) }
  end
end
