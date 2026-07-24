namespace :activity_suggestions do
  desc "Gera a sugestão de atividade do dia para cada professor (Heroku Scheduler: diariamente às 7h)"
  task generate: :environment do
    teachers = User.where(role: "teacher")
    if teachers.none?
      puts "Nenhum professor encontrado."
      next
    end

    teachers.each do |teacher|
      result = DailySuggestionAgentService.new(teacher: teacher).call
      if result[:skipped]
        puts "#{teacher.email}: já tem sugestão hoje (pulado)"
      elsif result[:success]
        puts "#{teacher.email}: sugestão criada — #{result[:suggestion].theme}"
      else
        puts "#{teacher.email}: ERRO — #{result[:error]}"
      end
    end
  end
end
