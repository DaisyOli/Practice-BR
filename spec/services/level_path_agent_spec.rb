require 'rails_helper'

# O agente do percurso propõe; quem decide é a Daisy. Os testes cobrem o que o
# app faz com a resposta — inclusive quando ela vem torta.
RSpec.describe LevelPathAgent do
  let(:client) { double("client") }
  let(:agent)  { described_class.new(client: client) }

  let!(:a1) { create(:activity, :A1, draft: false, title: "Oi, tudo bem?") }
  let!(:a2) { create(:activity, :A1, draft: false, title: "Minha rotina") }
  let!(:a3) { create(:activity, :A1, draft: false, title: "No restaurante") }

  def responde(tool, input, stop_reason: :tool_use)
    message = double(stop_reason: stop_reason,
                     content: [double(type: :tool_use, name: tool, input: input)])
    allow(client).to receive_message_chain(:messages, :stream).and_return(double(accumulated_message: message))
  end

  describe "#suggest_path" do
    it "devolve a ordem, os motivos e um tema por atividade" do
      responde("propose_path", {
        path: [{ activity_id: a1.id, reason: "curta" }, { activity_id: a3.id, reason: "vocabulário" }],
        themes: [{ activity_id: a1.id, theme: "Cumprimentos" }, { activity_id: a2.id, theme: "Rotina" }],
        summary: "Do cumprimento à rotina."
      })

      result = agent.suggest_path("A1")

      expect(result["path"].map { |p| p["activity_id"] }).to eq([a1.id, a3.id])
      expect(result["path"].first["title"]).to eq("Oi, tudo bem?")
      expect(result["themes"]).to eq(a1.id.to_s => "Cumprimentos", a2.id.to_s => "Rotina")
    end

    it "entende o input como texto JSON, que é como o streaming do SDK entrega" do
      responde("propose_path", { path: [{ activity_id: a1.id, reason: "curta" }], themes: [], summary: "" }.to_json)

      expect(agent.suggest_path("A1")["path"].first["activity_id"]).to eq(a1.id)
    end

    it "descarta id inventado, de outro nível ou repetido" do
      outra = create(:activity, :B1, draft: false)
      responde("propose_path", {
        path: [{ activity_id: 999_999, reason: "x" }, { activity_id: outra.id, reason: "x" },
               { activity_id: a2.id, reason: "ok" }, { activity_id: a2.id, reason: "de novo" }],
        themes: [], summary: ""
      })

      expect(agent.suggest_path("A1")["path"].map { |p| p["activity_id"] }).to eq([a2.id])
    end

    it "falha com mensagem clara quando não sobra nada válido" do
      responde("propose_path", { path: [{ activity_id: 999_999, reason: "x" }], themes: [], summary: "" })

      expect { agent.suggest_path("A1") }.to raise_error(LevelPathAgent::Failed, /nenhuma atividade válida/)
    end

    it "falha quando a IA recusa" do
      responde("propose_path", {}, stop_reason: :refusal)

      expect { agent.suggest_path("A1") }.to raise_error(LevelPathAgent::Failed, /recusou/)
    end

    it "não chama a IA para nível vazio" do
      expect { agent.suggest_path("C1") }.to raise_error(LevelPathAgent::Failed, /Nenhuma atividade/)
    end
  end

  describe "#evaluate" do
    let!(:nova) { create(:activity, :A1, draft: false, title: "Números") }

    before { Activity.set_path!("A1", [a1.id, a2.id]) }

    it "diz quem sai quando é troca" do
      responde("evaluate_new_activity", { decision: "replace", position: 2, replaces_activity_id: 123, reason: "melhor", theme: "Números" })

      result = agent.evaluate(nova)

      expect(result["decision"]).to eq("replace")
      expect(result["replaces_activity_id"]).to eq(a2.id) # o app confere, não confia no id da IA
    end

    it "troca numa posição vazia vira inserção" do
      responde("evaluate_new_activity", { decision: "replace", position: 5, replaces_activity_id: nil, reason: "x", theme: "Números" })

      expect(agent.evaluate(nova)["decision"]).to eq("insert")
    end

    it "posição fora do percurso vira 'fica fora'" do
      responde("evaluate_new_activity", { decision: "insert", position: 14, replaces_activity_id: nil, reason: "x", theme: "Números" })

      result = agent.evaluate(nova)
      expect(result["decision"]).to eq("none")
      expect(result["position"]).to be_nil
    end
  end
end
