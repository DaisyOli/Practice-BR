require 'rails_helper'

# A professora muda o nível do aluno dela — mas não pode mais deixar em branco.
# Antes o `nil` era aceito de propósito, e aluno sem nível não vê atividade
# nenhuma no catálogo: ficava sem acesso sem ninguém entender o motivo.
RSpec.describe "PATCH nível do aluno", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:professora) { create(:user, :teacher) }
  let(:aluno)      { create(:user, :student, level: "A2", invited_by_id: professora.id) }

  before { sign_in professora }

  it "atualiza para um nível válido" do
    patch teacher_student_level_path(aluno), params: { level: "B2" }

    expect(aluno.reload.level).to eq("B2")
    expect(flash[:notice]).to eq("Nível atualizado.")
  end

  it "recusa nível em branco e mantém o que já havia" do
    patch teacher_student_level_path(aluno), params: { level: "" }

    expect(aluno.reload.level).to eq("A2")
    expect(flash[:alert]).to include("Todo aluno precisa de um nível")
  end

  it "recusa nível fora da escala" do
    patch teacher_student_level_path(aluno), params: { level: "Z9" }

    expect(aluno.reload.level).to eq("A2")
    expect(flash[:alert]).to include("Todo aluno precisa de um nível")
  end

  it "não deixa mexer no aluno de outra professora" do
    outra = create(:user, :teacher)
    alheio = create(:user, :student, level: "A1", invited_by_id: outra.id)

    patch teacher_student_level_path(alheio), params: { level: "C1" }

    expect(alheio.reload.level).to eq("A1")
  end
end
