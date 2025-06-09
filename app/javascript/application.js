// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
// import "@hotwired/turbo-rails"
import "controllers"
import Rails from "@rails/ujs"
import Sortable from "sortablejs"

Rails.start()
window.Sortable = Sortable
