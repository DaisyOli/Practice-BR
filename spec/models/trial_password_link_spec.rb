require 'rails_helper'

# O link do email é o caminho de volta de quem nunca criou senha. Com as 6 horas
# padrão do Devise, quem se cadastrava à noite voltava no dia seguinte pra um
# link morto.
#
# O que separa os dois prazos é **ter senha**, não o papel na plataforma. Era
# `trial?` antes, e o proxy falhava na hora mais cara: no instante em que o
# webhook do Stripe muda o papel pra `student`, o link caía pra 6 horas e morria
# — deixando quem acabou de pagar sem caminho de volta.
RSpec.describe "Validade do link de volta de quem não tem senha", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  def link_ainda_vale?(user, depois_de:)
    raw = user.send_reset_password_instructions
    travel(depois_de) do
      User.reset_password_by_token(
        reset_password_token: raw,
        password: "senha-nova-123",
        password_confirmation: "senha-nova-123"
      ).errors.empty?
    end
  end

  context "conta de trial" do
    let(:user) { create(:user, :trial) }

    it "o link ainda vale no dia seguinte" do
      expect(link_ainda_vale?(user, depois_de: 1.day)).to be true
    end

    it "o link ainda vale perto do fim do teste de 7 dias" do
      expect(link_ainda_vale?(user, depois_de: 7.days)).to be true
    end

    it "o link não vale pra sempre" do
      expect(link_ainda_vale?(user, depois_de: 9.days)).to be false
    end
  end

  context "aluno pagante que já criou senha" do
    let(:user) { create(:user, :student) }

    it "continua com as 6 horas do Devise — prazo curto é a proteção certa" do
      expect(link_ainda_vale?(user, depois_de: 3.hours)).to be true
      expect(link_ainda_vale?(user, depois_de: 7.hours)).to be false
    end

    it "não herda o prazo longo" do
      expect(link_ainda_vale?(user, depois_de: 1.day)).to be false
    end
  end

  context "aluno pagante que nunca criou senha" do
    # Quem veio da landing, pagou e pulou o formulário da tela de sucesso. O papel
    # já é `student`, mas a senha no banco continua sendo a aleatória do cadastro:
    # o link do email é literalmente o único caminho de volta que ela tem.
    let(:user) { create(:user, :student, password_set_at: nil) }

    it "mantém o prazo longo — pagar não pode encurtar o único caminho de volta" do
      expect(link_ainda_vale?(user, depois_de: 3.days)).to be true
    end
  end

  context "professora" do
    it "também continua com as 6 horas" do
      teacher = create(:user, :teacher)

      expect(link_ainda_vale?(teacher, depois_de: 1.day)).to be false
    end
  end

  context "depois de criar a senha" do
    it "o prazo encurta na hora — o link volta a ser recuperação de verdade" do
      user = create(:user, :trial)
      user.update!(password: "escolhida-por-mim", password_confirmation: "escolhida-por-mim")

      expect(user.reload.passwordless?).to be false
      expect(link_ainda_vale?(user, depois_de: 1.day)).to be false
    end
  end
end
