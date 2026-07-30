class TeachersController < ApplicationController
  before_action :authenticate_user!, except: []
  before_action :require_teacher!, only: [:students, :student_profile, :student_activities, :student_written, :student_attestation, :update_student_level, :remove_student, :clear_student_comments, :more_ratings]

  def dashboard
  end

  def more_ratings
    offset   = params[:offset].to_i
    per_page = 3

    ratings = ActivityRating
      .joins(:activity, :user)
      .where(activities: { teacher_id: current_user.id })
      .where.not(comment: [nil, ''])
      .order(created_at: :desc)
      .includes(:user, :activity)
      .limit(per_page)
      .offset(offset)

    total = ActivityRating
      .joins(:activity)
      .where(activities: { teacher_id: current_user.id })
      .where.not(comment: [nil, ''])
      .count

    html = ratings.map { |rating|
      render_to_string(partial: 'teachers/rating_card', locals: { rating: rating }, formats: [:html])
    }.join

    render json: {
      html:        html,
      has_more:    (offset + per_page) < total,
      next_offset: offset + per_page
    }
  end

  def students
    @students = current_user.students
      .left_joins(:quiz_attempts)
      .where(
        "quiz_attempts.id IS NULL OR quiz_attempts.activity_id IN (?)",
        current_user.activities.select(:id)
      )
      .select(
        "users.*",
        "MAX(quiz_attempts.submitted_at) AS last_active",
        "COUNT(DISTINCT quiz_attempts.id) AS total_attempts",
        "ROUND(AVG(quiz_attempts.score)::numeric, 0) AS avg_score"
      )
      .group("users.id")
      .order(Arel.sql("MAX(quiz_attempts.submitted_at) DESC NULLS LAST"))
  end

  def student_profile
    @student = current_user.students.find(params[:id])
    scope = QuizAttempt
      .joins(:activity)
      .where(user_id: @student.id, activities: { teacher_id: current_user.id })

    # Aggregate metrics via SQL — no full record load
    @total_activities = scope.count
    @avg_score        = scope.average(:score)&.round || 0
    @best_score       = scope.maximum(:score)&.round || 0

    activity_ids = current_user.activities.pluck(:id)
    @days_active = QuizAttempt
      .where(user_id: @student.id, activity_id: activity_ids)
      .where("submitted_at >= ?", 30.days.ago)
      .pluck(:submitted_at).map { |t| t.to_date }.uniq.count

    # Load minimal fields to inspect JSONB columns for badges
    loaded = scope.select(:id, :results, :teacher_comments).to_a
    @pending_count = loaded.count { |a| a.open_ended_results.any? && a.teacher_comments.blank? }
    @total_written = loaded.count { |a| a.open_ended_results.any? }
    @has_comments  = loaded.any?  { |a| a.teacher_comments.present? }

    # Training hours (only attempts with both timestamps)
    @training_minutes = scope
      .where.not(started_at: nil)
      .select(:started_at, :submitted_at)
      .to_a
      .sum { |a| [(a.submitted_at - a.started_at) / 60, 120].min.to_i }
  rescue ActiveRecord::RecordNotFound
    redirect_to teacher_students_path, alert: "Aluno não encontrado."
  end

  def student_activities
    @student = current_user.students.find(params[:id])
    offset   = params[:offset].to_i
    attempts = QuizAttempt
      .joins(:activity)
      .where(user_id: @student.id, activities: { teacher_id: current_user.id })
      .includes(:activity)
      .order(submitted_at: :desc)
      .offset(offset)
      .limit(6)

    has_more = attempts.size == 6
    html = attempts.first(5).map { |a|
      render_to_string(partial: 'teachers/student_activity_row', locals: { attempt: a }, formats: [:html])
    }.join

    render json: { html: html, has_more: has_more, next_offset: offset + 5 }
  rescue ActiveRecord::RecordNotFound
    render json: { html: '', has_more: false, next_offset: 0 }
  end

  def student_written
    @student = current_user.students.find(params[:id])
    offset   = params[:offset].to_i
    per_page = 5

    all_written = QuizAttempt
      .joins(:activity)
      .where(user_id: @student.id, activities: { teacher_id: current_user.id })
      .includes(:activity)
      .order(submitted_at: :desc)
      .to_a
      .select { |a| a.open_ended_results.any? }

    items    = all_written.drop(offset).first(per_page)
    has_more = (offset + per_page) < all_written.size
    html = items.map { |a|
      render_to_string(partial: 'teachers/student_written_card', locals: { attempt: a }, formats: [:html])
    }.join

    render json: { html: html, has_more: has_more, next_offset: offset + per_page }
  rescue ActiveRecord::RecordNotFound
    render json: { html: '', has_more: false, next_offset: 0 }
  end

  def student_attestation
    @student = current_user.students.find(params[:id])
    @teacher = current_user
    @attempts = QuizAttempt
      .joins(:activity)
      .where(user_id: @student.id, activities: { teacher_id: current_user.id })
      .where.not(started_at: nil)
      .includes(:activity)
      .order(submitted_at: :asc)
    @total_minutes = @attempts.to_a.sum { |a| [(a.submitted_at - a.started_at) / 60, 120].min.to_i }
  rescue ActiveRecord::RecordNotFound
    redirect_to teacher_students_path
  end

  def update_student_level
    student = current_user.students.find(params[:id])
    new_level = params[:level].presence

    # Nível em branco não passa mais: todo aluno tem nível. Antes o `nil` era
    # aceito de propósito, e um aluno sem nível não vê atividade nenhuma no
    # catálogo — ficava sem acesso sem ninguém entender por quê.
    if User::CEFR_LEVELS.include?(new_level)
      student.update!(level: new_level)
      redirect_to teacher_student_profile_path(student), notice: "Nível atualizado."
    else
      redirect_to teacher_student_profile_path(student),
                  alert: "Todo aluno precisa de um nível. Escolha um entre A1 e C1."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to teacher_students_path
  end

  def remove_student
    student = current_user.students.find(params[:id])
    student.update!(invited_by_id: nil)
    redirect_to teacher_students_path, notice: "#{student.display_name} foi removido da sua lista de alunos."
  rescue ActiveRecord::RecordNotFound
    redirect_to teacher_students_path
  end

  def clear_student_comments
    student = current_user.students.find(params[:id])
    QuizAttempt
      .joins(:activity)
      .where(user_id: student.id, activities: { teacher_id: current_user.id })
      .update_all(teacher_comments: {})
    redirect_to teacher_student_profile_path(student), notice: "Feedbacks apagados."
  rescue ActiveRecord::RecordNotFound
    redirect_to teacher_students_path
  end

  private

  def require_teacher!
    redirect_to root_path unless current_user&.teacher?
  end
end
