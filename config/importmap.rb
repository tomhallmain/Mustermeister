# BEFORE other JS imports
pin "jquery", to: "https://ga.jspm.io/npm:jquery@3.7.1/dist/jquery.js"
pin "rails_admin", preload: true
pin "@rails/ujs", to: "https://ga.jspm.io/npm:@rails/ujs@7.1.3/app/assets/javascripts/rails-ujs.esm.js"
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.0/Sortable.js"

# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "kanban_filter_persistence", to: "kanban_filter_persistence.js"
pin "kanban", to: "kanban.js"
# pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"

