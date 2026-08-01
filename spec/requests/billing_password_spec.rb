require 'rails_helper'

# Depois de pagar, a senha. Quem vem da landing atravessa o trial inteiro sem
# criar uma — e até aqui o acesso ficava pendurado em duas coisas que vencem: o
# cookie de "lembrar de mim" e o link do email. Duas semanas depois de pagar, a
# pessoa encontrava uma tela de login pedindo uma senha que ela nunca escolheu.
RSpec.describe "Senha depois do pagamento", type: :request do
  include Devise::Test::IntegrationHelpers

  # O ERB escapa apóstrofo: "d'une" vira "d&#39;une" no HTML.
  def texto
    CGI.unescapeHTML(response.body)
  end

  describe "GET /assinar/sucesso" do
    it "pede a senha de quem nunca criou uma" do
      sign_in create(:user, :student, password_set_at: nil, language: "fr")

      get billing_success_path

      expect(texto).to include("Encore deux petites choses")
      expect(response.body).to include("user[password]")
    end

    it "pergunta como a pessoa quer ser chamada" do
      # Quem vem da landing atravessa o teste inteiro sem nome: lá o cadastro é
      # só email e nível. Sem perguntar aqui, a dashboard cumprimenta com um
      # "Olá!" seco pra sempre.
      sign_in create(:user, :student, password_set_at: nil, language: "fr")

      get billing_success_path

      expect(texto).to include("Comment souhaitez-vous qu'on vous appelle ?")
      expect(response.body).to include("user[name]")
    end

    it "não pede nada de quem já tem senha" do
      sign_in create(:user, :student)

      get billing_success_path

      expect(response.body).not_to include("user[password]")
    end

    it "fala a língua do cadastro, não a do navegador" do
      sign_in create(:user, :student, password_set_at: nil, language: "pt")

      get billing_success_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "fr-FR,fr;q=0.9" }

      expect(texto).to include("Faltam só duas coisinhas")
      expect(texto).to include("Como você quer ser chamado?")
    end

    it "deixa uma saída — ninguém fica preso numa tela logo depois de pagar" do
      sign_in create(:user, :student, password_set_at: nil)

      get billing_success_path

      expect(response.body).to include(student_dashboard_path)
    end
  end

  describe "POST /assinar/senha" do
    let(:user) { create(:user, :student, password_set_at: nil) }

    before { sign_in user }

    def criar_senha(senha, confirmacao = senha, nome: nil)
      post billing_password_path,
           params: { user: { name: nome, password: senha, password_confirmation: confirmacao } }
    end

    it "guarda o nome junto com a senha" do
      criar_senha("minha-senha-nova", nome: "Camille")

      expect(user.reload.name).to eq("Camille")
      expect(user.greeting_name).to eq("Camille")
    end

    it "não apaga o nome de quem deixou o campo vazio" do
      user.update_columns(name: "Já Tinha Nome")

      criar_senha("minha-senha-nova", nome: "   ")

      expect(user.reload.name).to eq("Já Tinha Nome")
    end

    it "recusa nome maior que o limite sem perder a senha digitada" do
      criar_senha("minha-senha-nova", nome: "x" * 51)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.passwordless?).to be true
    end

    it "salva a senha e leva pra dashboard" do
      criar_senha("minha-senha-nova")

      expect(response).to redirect_to(student_dashboard_path)
      expect(user.reload.valid_password?("minha-senha-nova")).to be true
    end

    it "marca que a senha passou a ser escolhida pela pessoa" do
      criar_senha("minha-senha-nova")

      expect(user.reload.password_set_at).to be_present
      expect(user.passwordless?).to be false
    end

    it "mantém a pessoa dentro — trocar a senha muda o salt da sessão" do
      criar_senha("minha-senha-nova")

      # Sem reemitir a sessão, a página seguinte cairia no login. Logo depois de
      # pagar, seria o pior momento possível pra isso acontecer.
      get student_dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it "recusa confirmação diferente e devolve a tela com o erro visível" do
      criar_senha("minha-senha-nova", "outra-coisa")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.password_set_at).to be_nil
      # O erro precisa aparecer ao lado dos campos, junto com o formulário.
      expect(texto).to match(/confirma[çc]/i)
      expect(response.body).to include("user[password]")
    end

    it "recusa senha curta demais pro Devise" do
      criar_senha("123")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.passwordless?).to be true
    end

    it "não vira atalho pra trocar a senha de quem já tem uma" do
      # Sem pedir a senha atual, esta rota seria uma troca de senha silenciosa
      # pra qualquer sessão roubada. A exceção só vale pra quem não tem senha
      # nenhuma pra informar.
      com_senha = create(:user, :student)
      sign_in com_senha

      criar_senha("senha-de-invasor")

      expect(response).to redirect_to(student_dashboard_path)
      expect(com_senha.reload.valid_password?("password123")).to be true
    end
  end
end
