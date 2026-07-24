namespace :activity_suggestions do
  desc "Gera a sugestão de atividade do dia para a professora (Heroku Scheduler: diariamente às 7h)"
  task generate: :environment do
    # Feature ainda não lançada para outros professores — restrita à Daisy por
    # enquanto, mesmo padrão de Admin::ActivitySuggestionsController::TEACHER_EMAIL.
    teacher = User.find_by(email: Admin::ActivitySuggestionsController::TEACHER_EMAIL)
    unless teacher
      puts "Professora não encontrada."
      next
    end

    result = DailySuggestionAgentService.new(teacher: teacher).call
    if result[:skipped] && result[:reason] == "too_recent"
      puts "#{teacher.email}: última sugestão foi há menos de #{DailySuggestionAgentService::MIN_INTERVAL.inspect} (pulado)"
    elsif result[:skipped]
      puts "#{teacher.email}: já tem sugestão pendente (pulado)"
    elsif result[:success]
      puts "#{teacher.email}: sugestão criada — #{result[:suggestion].theme}"
    else
      puts "#{teacher.email}: ERRO — #{result[:error]}"
    end
  end
end
