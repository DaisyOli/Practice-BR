module Admin
  class DashboardController < BaseController
    def index
      @summary  = platform_summary
      @teachers = teacher_stats
      @trials   = User.trials.order(created_at: :desc)
      @trial_summary = trial_summary
      # Contas de teste fora da conta: com 5 pessoas no mês, uma conta da Daisy
      # muda a taxa inteira. Ids em TRIAL_FUNNEL_EXCLUDE_IDS (separados por vírgula).
      @trial_funnel = TrialFunnel.new(from: 30.days.ago,
                                      exclude_ids: ENV["TRIAL_FUNNEL_EXCLUDE_IDS"].to_s.split(",")).stats
    end

    private

    def platform_summary
      {
        teachers:            User.teachers.count,
        students:            User.students.count,
        trials_active:       User.trials.where("trial_expires_at > ?", Time.current).where("trial_activities_used < 3").count,
        activities_published: Activity.where(draft: false).count
      }
    end

    def teacher_stats
      User.teachers.order(:name).map do |teacher|
        activity_ids = Activity.where(teacher_id: teacher.id).pluck(:id)
        attempts = QuizAttempt.where(activity_id: activity_ids).where.not(submitted_at: nil)

        {
          teacher:              teacher,
          activities_total:     activity_ids.size,
          activities_published: Activity.where(id: activity_ids, draft: false).count,
          students_count:       User.where(invited_by_id: teacher.id, role: "student").count,
          total_attempts:       attempts.count,
          avg_score:            attempts.average(:score)&.round(1),
          last_activity_at:     Activity.where(teacher_id: teacher.id).maximum(:created_at)
        }
      end
    end

    def trial_summary
      {
        total:     User.trials.count,
        active:    User.trials.where("trial_expires_at > ?", Time.current).where("trial_activities_used < 3").count,
        exhausted: User.trials.where("trial_activities_used >= 3").count,
        expired:   User.trials.where("trial_expires_at <= ?", Time.current).count
      }
    end
  end
end
