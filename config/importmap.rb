# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@rails/ujs", to: "@rails--ujs.js" # @7.1.3
# Removido jQuery e jquery-ujs do importmap para evitar carregamento duplo, 
# pois já estamos usando jQuery via CDN e rails-ujs via importmap
# pin "jquery", to: "https://cdn.jsdelivr.net/npm/jquery@3.7.1/dist/jquery.min.js"
# pin "jquery_ujs", to: "https://cdn.jsdelivr.net/npm/jquery-ujs@1.2.3/src/rails.min.js"
pin "sortable", to: "vendor/sortable.min.js", preload: true
pin_all_from "app/javascript/vendor", under: "vendor"
pin "quiz_results", to: "quiz_results.js", preload: true
pin "answer_event", to: "answer_event.js"
pin "student_dashboard", to: "student_dashboard.js"
pin "teacher_dashboard", to: "teacher_dashboard.js"
