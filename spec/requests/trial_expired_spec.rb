require 'rails_helper'

# A tela de fim de trial virou o momento da conversão. Dois testes de conteúdo e
# um de idioma: é a última coisa que a pessoa lê antes de decidir pagar, e ela
# precisa ler na própria língua.
RSpec.describe "Fim do trial", type: :request do
  include Devise::Test::IntegrationHelpers

  # Trial esgotado: usou as 3 atividades. É assim que se chega nesta tela.
  let(:user) { create(:user, :trial, trial_activities_used: 3) }

  before { sign_in user }

  def get_expired(accept_language)
    get trial_expired_path, headers: { "HTTP_ACCEPT_LANGUAGE" => accept_language }
  end

  # O ERB escapa apóstrofo: "S'abonner" vira "S&#39;abonner" no HTML. Comparar
  # com o texto desescapado deixa os testes legíveis e testando o que a pessoa lê.
  def texto
    CGI.unescapeHTML(response.body)
  end

  it "fala francês com navegador francês" do
    get_expired("fr-FR,fr;q=0.9")

    expect(texto).to include("Votre essai est terminé")
    expect(texto).to include("S'abonner maintenant")
  end

  it "fala inglês com navegador inglês" do
    get_expired("en-US,en;q=0.9")

    expect(texto).to include("Your trial has ended")
    expect(texto).to include("Subscribe now")
  end

  it "fala português com navegador português" do
    get_expired("pt-BR,pt;q=0.9")

    expect(texto).to include("Seu acesso de teste encerrou")
    expect(texto).to include("Assinar agora")
  end

  it "cai no francês quando o navegador pede um idioma que não temos" do
    get_expired("de-DE,de;q=0.9")

    expect(texto).to include("Votre essai est terminé")
  end

  it "respeita a ordem de preferência do navegador, não a ordem da lista" do
    # Alemão primeiro (não temos), inglês depois: tem que sair inglês.
    get_expired("de-DE,de;q=0.9,en;q=0.8")

    expect(texto).to include("Your trial has ended")
  end

  it "manda Vary: Accept-Language, pra nenhum cache servir o idioma errado" do
    get_expired("fr-FR")

    expect(response.headers["Vary"]).to include("Accept-Language")
  end

  describe "o que saiu da tela" do
    it "não tem mais o botão de falar com professor" do
      get_expired("pt-BR")

      expect(texto).not_to include("Falar com um professor")
    end

    it "não anuncia preço no botão — a escolha do plano é na tela seguinte" do
      get_expired("pt-BR")

      expect(texto).not_to include("9,99")
      expect(texto).not_to include("9.99")
    end

    it "leva pra tela de assinatura" do
      get_expired("pt-BR")

      expect(response.body).to include(billing_new_path)
    end
  end
end
