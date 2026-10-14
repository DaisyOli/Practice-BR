# Emails para as professoras. Em português: é a língua de trabalho delas na
# plataforma (a interface é só em português, ver a decisão de I18n).
class TeacherMailer < ApplicationMailer
  # A admin atribuiu um aluno a esta professora (TeachersController#assign_student).
  # Sem isto ela só descobriria abrindo a lista.
  def student_assigned(teacher, student)
    @teacher = teacher
    @student = student
    @url     = teacher_student_profile_url(student)

    mail(to: teacher.email,
         subject: "Nova pessoa na sua turma: #{student.display_name} · #{student.level}")
  end
end
