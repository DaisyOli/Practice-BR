require 'rails_helper'

# O fluxo de aprovação: o agente propõe em segundo plano, a Daisy revisa e salva.
RSpec.describe "Agente do percurso", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin) }
  let!(:a1) { create(:activity, :A1, draft: false, title: "Oi, tudo bem?") }
  let!(:a2) { create(:activity, :A1, draft: false, title: "Minha rotina") }

  before { sign_in admin }

  describe "Sugerir com o agente" do
    it "pede em segundo plano e não pede de novo enquanto ele trabalha" do
      expect {
        post admin_suggest_path_path, params: { level: "A1" }
        post admin_suggest_path_path, params: { level: "A1" }
      }.to have_enqueued_job(LevelPathJob).once

      get admin_path_path
      expect(response.body).to include("O agente está lendo as atividades do A1")
      expect(response.body).to include("window.location.reload")
    end

    it "mostra a proposta já preenchida, com o motivo de cada posição, sem salvar nada" do
      PathSuggestion.create!(level: "A1", kind: "full", status: "done", payload: {
        "path" => [{ "activity_id" => a2.id, "reason" => "texto de 60 palavras" }],
        "themes" => { a2.id.to_s => "Rotina" }, "summary" => "Comece pela rotina."
      })

      get admin_path_path

      expect(response.body).to include("Sugestão do agente")
      expect(response.body).to include("texto de 60 palavras")
      expect(response.body).to include('value="Rotina"')
      expect(a2.reload.path_position).to be_nil
    end

    it "salvar grava percurso e temas e encerra a proposta" do
      proposta = PathSuggestion.create!(level: "A1", kind: "full", status: "done",
                                        payload: { "path" => [], "themes" => {}, "summary" => "" })

      patch admin_path_path, params: { path: { "A1" => { "1" => a2.id, "2" => a1.id } },
                                       themes: { a1.id.to_s => " Cumprimentos ", a2.id.to_s => "" } }

      expect(a2.reload.path_position).to eq(1)
      expect(a1.reload.theme).to eq("Cumprimentos")
      expect(proposta.reload.resolution).to eq("saved")
    end

    it "descartar volta ao que estava salvo" do
      Activity.set_path!("A1", [a1.id])
      proposta = PathSuggestion.create!(level: "A1", kind: "full", status: "done",
                                        payload: { "path" => [{ "activity_id" => a2.id, "reason" => "x" }], "themes" => {}, "summary" => "" })

      post admin_dismiss_path_suggestion_path(proposta)

      expect(proposta.reload.resolution).to eq("ignored")
      expect(a1.reload.path_position).to eq(1)
    end
  end

  describe "atividade nova" do
    let!(:nova) { create(:activity, :A1, draft: false, title: "Números") }

    before { Activity.set_path!("A1", [a1.id, a2.id]) }

    def sugestao(decision, position)
      PathSuggestion.create!(level: "A1", kind: "new_activity", status: "done", activity: nova,
                             payload: { "decision" => decision, "position" => position,
                                        "replaces_activity_id" => (decision == "replace" ? a2.id : nil),
                                        "reason" => "trabalha números", "theme" => "Números" })
    end

    it "aparece no painel com Aceitar e Ignorar" do
      sugestao("replace", 2)
      get admin_path_path

      expect(response.body).to include("Atividades novas para o percurso")
      expect(CGI.unescapeHTML(response.body)).to include("no lugar de \"Minha rotina\"")
    end

    it "aceitar uma troca substitui a posição" do
      post admin_accept_path_suggestion_path(sugestao("replace", 2))

      expect(nova.reload.path_position).to eq(2)
      expect(a2.reload.path_position).to be_nil
    end

    it "aceitar uma inserção empurra as seguintes" do
      post admin_accept_path_suggestion_path(sugestao("insert", 1))

      expect([nova, a1, a2].map { |a| a.reload.path_position }).to eq([1, 2, 3])
    end

    it "'fica fora' não pede nada" do
      sugestao("none", nil)
      get admin_path_path

      expect(response.body).not_to include("Atividades novas para o percurso")
    end
  end

  describe "publicar pede a avaliação" do
    around do |ex|
      Rails.configuration.x.level_path_on_publish = true
      ex.run
    ensure
      Rails.configuration.x.level_path_on_publish = nil
    end

    it "uma vez por atividade, ao sair do rascunho" do
      rascunho = create(:activity, :A1, draft: true)

      expect { rascunho.update!(draft: false); rascunho.update!(title: "Outro título") }
        .to have_enqueued_job(LevelPathJob).once
      expect(PathSuggestion.where(activity: rascunho, kind: "new_activity").count).to eq(1)
    end

    it "fica desligado fora de produção" do
      Rails.configuration.x.level_path_on_publish = nil

      expect { create(:activity, :A1, draft: false) }.not_to have_enqueued_job(LevelPathJob)
    end
  end

  describe "LevelPathJob" do
    it "não chama a IA duas vezes para a mesma sugestão" do
      s = PathSuggestion.create!(level: "A1", kind: "full", status: "running")
      expect(LevelPathAgent).not_to receive(:new)

      LevelPathJob.perform_now(s.id)
    end

    it "registra a falha em vez de deixar a tela girando" do
      s = PathSuggestion.create!(level: "A1", kind: "full")
      allow_any_instance_of(LevelPathAgent).to receive(:suggest_path).and_raise(RuntimeError, "formato estranho")

      LevelPathJob.perform_now(s.id)

      expect(s.reload.status).to eq("failed")
      get admin_path_path
      expect(response.body).to include("A última sugestão não deu certo")
    end

    it "atividade nova: grava o tema na hora e deixa a posição para aprovação" do
      nova = create(:activity, :A1, draft: false)
      s = PathSuggestion.create!(level: "A1", kind: "new_activity", activity: nova)
      allow_any_instance_of(LevelPathAgent).to receive(:evaluate).and_return(
        "decision" => "insert", "position" => 1, "replaces_activity_id" => nil, "reason" => "x", "theme" => "Números")

      LevelPathJob.perform_now(s.id)

      expect(nova.reload.theme).to eq("Números")
      expect(nova.path_position).to be_nil
      expect(s.reload.status).to eq("done")
    end
  end
end
