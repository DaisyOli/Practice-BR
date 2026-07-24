require 'rails_helper'

RSpec.describe DailySuggestionAgentService do
  let(:teacher) { create(:user, :teacher) }
  let(:client)  { instance_double(Anthropic::Client) }
  let(:messages_resource) { double("messages") }

  before do
    allow(Anthropic::Client).to receive(:new).and_return(client)
    allow(client).to receive(:messages).and_return(messages_resource)
  end

  def tool_use_block(name:, input:, id: "toolu_#{name}")
    double(type: :tool_use, id: id, name: name, input: input)
  end

  def response(stop_reason:, content:)
    double(stop_reason: stop_reason, content: content)
  end

  describe '#call' do
    context 'quando a IA consulta uma ferramenta e depois propõe' do
      let(:recent_themes_call) do
        response(stop_reason: :tool_use, content: [
          tool_use_block(name: "recent_themes", input: { level: "A1" })
        ])
      end
      let(:final_call) do
        response(stop_reason: :tool_use, content: [
          tool_use_block(
            name: "propose_suggestion",
            input: { theme: "Pedir comida por app de delivery", level: "A1", rationale: "Nenhum tema recente sobre delivery no catálogo." }
          )
        ])
      end

      before do
        allow(messages_resource).to receive(:create).and_return(recent_themes_call, final_call)
      end

      it 'cria a sugestão com o tema, nível e justificativa propostos' do
        result = described_class.new(teacher: teacher).call

        expect(result[:success]).to be true
        suggestion = result[:suggestion]
        expect(suggestion).to be_a(ActivitySuggestion)
        expect(suggestion.theme).to eq("Pedir comida por app de delivery")
        expect(suggestion.level_hint).to eq("A1")
        expect(suggestion.rationale).to include("delivery")
        expect(suggestion.status).to eq("pending")
      end

      it 'chama a ferramenta duas vezes (pesquisa + proposta final)' do
        described_class.new(teacher: teacher).call
        expect(messages_resource).to have_received(:create).twice
      end
    end

    context 'quando já existe uma sugestão pendente (qualquer data)' do
      before { create(:activity_suggestion, teacher: teacher, status: "pending", created_at: 30.days.ago) }

      it 'não chama a IA e retorna skipped, mesmo se a pendente for antiga' do
        result = described_class.new(teacher: teacher).call

        expect(result).to eq(skipped: true, reason: "already_has_suggestion")
        expect(client).not_to have_received(:messages)
      end
    end

    context 'quando a última sugestão (já revisada) foi criada há menos de 7 dias' do
      before { create(:activity_suggestion, teacher: teacher, status: "approved", created_at: 2.days.ago) }

      it 'não gera outra ainda — respeita o intervalo semanal' do
        result = described_class.new(teacher: teacher).call

        expect(result).to eq(skipped: true, reason: "too_recent")
        expect(client).not_to have_received(:messages)
      end
    end

    context 'quando a última sugestão foi criada há mais de 7 dias' do
      before { create(:activity_suggestion, teacher: teacher, status: "rejected", created_at: 8.days.ago) }
      let(:final_call) do
        response(stop_reason: :tool_use, content: [
          tool_use_block(name: "propose_suggestion", input: { theme: "Novo tema", level: "A2", rationale: "Justificativa." })
        ])
      end

      before { allow(messages_resource).to receive(:create).and_return(final_call) }

      it 'gera uma nova sugestão normalmente' do
        result = described_class.new(teacher: teacher).call
        expect(result[:success]).to be true
      end
    end

    context 'quando a IA termina sem chamar propose_suggestion' do
      before do
        allow(messages_resource).to receive(:create).and_return(
          response(stop_reason: :end_turn, content: [double(type: :text, text: "Não sei o que sugerir.")])
        )
      end

      it 'retorna erro em vez de arriscar um palpite' do
        result = described_class.new(teacher: teacher).call
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context 'quando a IA se recusa (refusal)' do
      before do
        allow(messages_resource).to receive(:create).and_return(response(stop_reason: :refusal, content: []))
      end

      it 'retorna erro sem estourar' do
        result = described_class.new(teacher: teacher).call
        expect(result[:success]).to be false
      end
    end
  end

  describe 'ferramentas de pesquisa (dados esparsos)' do
    let(:service) { described_class.new(teacher: teacher) }

    it 'recent_themes avisa quando não há atividades no nível' do
      expect(service.send(:recent_themes, "C1")).to include("Nenhuma atividade recente")
    end

    it 'rating_insights avisa quando não há avaliações suficientes' do
      expect(service.send(:rating_insights, "C1")).to include("Dados insuficientes")
    end

    it 'low_performing_topics avisa quando não há tentativas suficientes' do
      expect(service.send(:low_performing_topics, "C1")).to include("Dados insuficientes")
    end

    context 'com dados reais' do
      let(:activity) { create(:activity, :A2, teacher: teacher, ai_generated: true, title: "Café da manhã") }

      it 'recent_themes retorna os títulos existentes' do
        activity
        expect(service.send(:recent_themes, "A2")).to include("Café da manhã")
      end

      it 'rating_insights agrega estrelas quando há avaliações suficientes' do
        3.times { create(:activity_rating, activity: activity, stars: 5) }
        expect(service.send(:rating_insights, "A2")).to include("Café da manhã")
      end

      it 'low_performing_topics agrega notas de quiz quando há tentativas suficientes' do
        activity.update!(draft: false)
        3.times { create(:quiz_attempt, activity: activity, score: 20.0, submitted_at: Time.current) }
        expect(service.send(:low_performing_topics, "A2")).to include("Café da manhã")
      end
    end
  end
end
