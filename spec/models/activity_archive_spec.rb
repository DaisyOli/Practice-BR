require 'rails_helper'

# Arquivar (ponto 1.5, 17/11/2026): sai de circulação, o histórico fica.
RSpec.describe Activity, "arquivar" do
  let(:activity) { create(:activity, :B1, draft: false) }

  it "a arquivada some de \"publicada\", que é o que o aluno vê em todo lugar" do
    activity.archive!

    expect(Activity.published).not_to include(activity)
    expect(Activity.archived).to include(activity)
    expect(activity).to be_archived
  end

  it "arquivar tira do percurso, e desarquivar devolve à circulação" do
    Activity.set_path!("B1", [activity.id])
    expect(activity.reload.path_position).to eq(1)

    activity.archive!
    expect(activity.reload.path_position).to be_nil

    activity.unarchive!
    expect(Activity.published).to include(activity)
  end

  it "o histórico dos alunos fica" do
    create(:quiz_attempt, activity: activity)
    activity.archive!

    expect(activity.quiz_attempts.count).to eq(1)
  end

  it "conhece as pílulas publicadas que saíram dela" do
    publicada = create(:activity, :B1, draft: false, pill: true, source_activity: activity, series_key: "s", series_position: 1)
    create(:activity, :B1, draft: true, pill: true, source_activity: activity, series_key: "s", series_position: 2)

    expect(activity.published_adapted_pills).to eq([publicada])
  end
end
