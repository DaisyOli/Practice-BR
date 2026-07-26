require 'rails_helper'

RSpec.describe Activity, type: :model do
  describe 'validations' do
    subject { build(:activity) }
    
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:level) }
  end

  describe 'associations' do
    it { should belong_to(:teacher).class_name('User') }
    it { should have_many(:questions).dependent(:destroy) }
    it { should have_many(:quiz_attempts).dependent(:destroy) }
    it { should have_many(:suggestions).dependent(:destroy) }
  end

  describe 'enums' do
    it 'defines correct levels' do
      expect(Activity.levels.keys).to include('A1', 'A2', 'B1', 'B2', 'C1')
      expect(Activity.levels.keys).not_to include('C2')
    end
    
    it 'allows setting valid levels' do
      activity = build(:activity)
      ['A1', 'A2', 'B1', 'B2', 'C1'].each do |level|
        expect { activity.level = level }.not_to raise_error
      end
    end
    
    it 'rejects invalid levels' do
      activity = build(:activity)
      expect { activity.level = 'INVALID' }.to raise_error(ArgumentError)
    end
  end

  describe 'factory' do
    it 'creates valid activity' do
      activity = create(:activity)
      expect(activity).to be_valid
      expect(activity.teacher).to be_present
      expect(activity.teacher.teacher?).to be true
    end

    it 'creates activity with specific teacher' do
      teacher = create(:user, :teacher)
      activity = create(:activity, teacher: teacher)
      expect(activity.teacher).to eq(teacher)
    end
  end

  describe 'methods' do
    let(:activity) { create(:activity) }

    describe '#level_color_class' do
      it 'returns correct CSS class for A1 level' do
        activity.update(level: 'A1')
        expect(activity.level_color_class).to eq('bg-info')
      end

      it 'returns correct CSS class for A2 level' do
        activity.update(level: 'A2')
        expect(activity.level_color_class).to eq('bg-primary')
      end

      it 'returns correct CSS class for B1 level' do
        activity.update(level: 'B1')
        expect(activity.level_color_class).to eq('bg-success')
      end

      it 'returns correct CSS class for B2 level' do
        activity.update(level: 'B2')
        expect(activity.level_color_class).to eq('bg-warning')
      end

      it 'returns correct CSS class for C1 level' do
        activity.update(level: 'C1')
        expect(activity.level_color_class).to eq('bg-danger')
      end

      it 'returns default CSS class for unknown level' do
        # Simular um nível desconhecido modificando diretamente
        allow(activity).to receive(:level).and_return('UNKNOWN')
        expect(activity.level_color_class).to eq('bg-secondary')
      end
    end
    
    describe 'cache clearing' do
      it 'clears cache after commit' do
        expect(Rails.cache).to receive(:delete_matched).at_least(:once)
        activity.update(title: 'Updated Title')
      end
    end
  end

  describe 'slug' do
    it 'gera o slug a partir do título na criação' do
      activity = create(:activity, title: 'Mistério em Armação')
      expect(activity.slug).to eq('misterio-em-armacao')
    end

    # Regressão: renomear a atividade mudava o slug, e quem já tinha a URL
    # antiga aberta (aluno no meio do exercício, link do WhatsApp já enviado)
    # caía em 404 na hora de enviar/abrir de novo.
    it 'mantém o slug estável quando o título é editado depois' do
      activity = create(:activity, title: 'Mistério em Armação')
      original_slug = activity.slug

      activity.update(title: 'Novo Título Completamente Diferente')

      expect(activity.reload.slug).to eq(original_slug)
    end

    it 'gera slugs únicos para títulos iguais' do
      first = create(:activity, title: 'Mesmo Título')
      second = create(:activity, title: 'Mesmo Título')

      expect(first.slug).not_to eq(second.slug)
    end
  end

  describe 'with questions' do
    let(:activity) { create(:activity) }
    
    it 'can have multiple questions' do
      question1 = create(:question, activity: activity)
      question2 = create(:question, :multiple_choice, activity: activity)
      
      expect(activity.questions.count).to eq(2)
      expect(activity.questions).to include(question1, question2)
    end

    it 'destroys questions when activity is destroyed' do
      question = create(:question, activity: activity)
      question_id = question.id
      
      expect { activity.destroy }.to change { Question.count }.by(-1)
      expect(Question.find_by(id: question_id)).to be_nil
    end
  end

  describe 'with quiz attempts' do
    let(:activity) { create(:activity) }
    let(:student) { create(:user, :student) }
    
    it 'can have multiple quiz attempts' do
      attempt1 = create(:quiz_attempt, activity: activity, user: student)
      student2 = create(:user, :student)
      attempt2 = create(:quiz_attempt, activity: activity, user: student2)
      
      expect(activity.quiz_attempts.count).to eq(2)
      expect(activity.quiz_attempts).to include(attempt1, attempt2)
    end

    it 'destroys quiz attempts when activity is destroyed' do
      attempt = create(:quiz_attempt, activity: activity, user: student)
      attempt_id = attempt.id
      
      expect { activity.destroy }.to change { QuizAttempt.count }.by(-1)
      expect(QuizAttempt.find_by(id: attempt_id)).to be_nil
    end
  end

  describe 'scopes and queries' do
    let!(:teacher1) { create(:user, :teacher) }
    let!(:teacher2) { create(:user, :teacher) }
    let!(:activity_a1) { create(:activity, level: 'A1', teacher: teacher1) }
    let!(:activity_b1) { create(:activity, level: 'B1', teacher: teacher1) }
    let!(:activity_c1) { create(:activity, level: 'C1', teacher: teacher2) }

    it 'can filter by teacher' do
      teacher1_activities = Activity.where(teacher: teacher1)
      expect(teacher1_activities).to include(activity_a1, activity_b1)
      expect(teacher1_activities).not_to include(activity_c1)
    end

    it 'can filter by level' do
      a1_activities = Activity.where(level: 'A1')
      expect(a1_activities).to include(activity_a1)
      expect(a1_activities).not_to include(activity_b1, activity_c1)
    end
  end
end 