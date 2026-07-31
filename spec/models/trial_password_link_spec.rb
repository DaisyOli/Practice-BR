require 'rails_helper'

# O link do email é o caminho de volta de quem nunca criou senha. Com as 6 horas
# padrão do Devise, quem se cadastrava à noite voltava no dia seguinte pra um
# link morto.
#
# O teste que mais importa aqui é o último: o prazo maior vale SÓ pro trial.
# Aluno pagante tem que continuar com as 6 horas, porque ali o link é uma
# recuperação de senha de verdade.
RSpec.describe "Validade do link de volta do trial", type: :model do
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

  context "aluno pagante" do
    let(:user) { create(:user, :student) }

    it "continua com as 6 horas do Devise — prazo curto é a proteção certa" do
      expect(link_ainda_vale?(user, depois_de: 3.hours)).to be true
      expect(link_ainda_vale?(user, depois_de: 7.hours)).to be false
    end

    it "não herda o prazo do trial" do
      expect(link_ainda_vale?(user, depois_de: 1.day)).to be false
    end
  end

  context "professora" do
    it "também continua com as 6 horas" do
      teacher = create(:user, :teacher)

      expect(link_ainda_vale?(teacher, depois_de: 1.day)).to be false
    end
  end
end
