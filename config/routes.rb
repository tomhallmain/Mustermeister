Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Health and backup status endpoints
  get "health" => "health#show", as: :health_check
  get "health/backup" => "health#backup_status", as: :backup_status

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :api do
    get "tools/:tool_name", to: "tools#show", as: :tool
    post "tools/:tool_name", to: "tools#create"
  end

  # Configure Devise routes
  devise_for :users, controllers: {
    sessions: 'users/sessions' # Path to custom sessions controller
  }

  # Mount RailsAdmin
  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'

  # Defines the root path route ("/")
  root "projects#index"

  # Archives routes
  get '/archives', to: 'tasks#archive_index', as: :archives
  post '/archives/bulk', to: 'tasks#bulk_archive', as: :bulk_archive

  # Reschedule routes
  get '/reschedule', to: 'tasks#reschedule_index', as: :reschedule
  post '/reschedule/bulk', to: 'tasks#bulk_reschedule', as: :bulk_reschedule

  # Merge tasks routes
  get '/merge_tasks', to: 'tasks#merge_tasks', as: :merge_tasks
  post '/merge_tasks', to: 'tasks#merge_tasks_execute', as: :merge_tasks_execute

  resources :projects do
    resources :tasks, shallow: true
    resources :statuses, shallow: true, only: [:new, :create, :edit, :update, :destroy] do
      member do
        patch 'move_up'
        patch 'move_down'
      end
    end
    member do
      get 'report'
      post 'reprioritize'
      post 'recategorize'
      get 'merge'
      post 'merge_execute'
    end
    collection do
      get 'all_reports'
    end
    resources :comments, only: [:create, :update, :destroy]
    resources :project_memberships, shallow: true, only: [:create, :update, :destroy]
  end

  resources :tasks do
    member do
      patch :toggle
      post :archive
      patch :refresh
      post :translate
    end
    resources :comments, only: [:create, :update, :destroy], shallow: true
    resources :attachments, only: [:create, :destroy], shallow: true do
      member do
        get :download
      end
    end
  end

  resources :tags, except: [:show]

  resources :task_categories, except: [:show]

  resources :recurring_task_templates, path: 'recurring_tasks' do
    member do
      patch :toggle
    end
  end

  resources :notifications, only: [:index] do
    member do
      patch :mark_read
    end
    collection do
      patch :mark_all_read
    end
  end

  # User profile
  get 'profile', to: 'users#profile', as: :profile
  patch 'profile', to: 'users#update'
  get 'profile/export', to: 'users#export_data', as: :export_data
  # The encrypted ZIP export carries a password in its params, which the
  # profile page submits via this POST route (not the GET one above, used
  # only for the plain JSON download link) so the password never ends up in
  # a URL - browser history, server access logs, Referer headers, etc.
  post 'profile/export', to: 'users#export_data'
  post 'profile/import', to: 'users#import_data', as: :import_data
  post 'profile/api_token', to: 'users#regenerate_api_token', as: :regenerate_api_token
  post 'profile/api_token_scope', to: 'users#update_api_token_scope', as: :update_api_token_scope

  # CSP violation reporting endpoint
  post '/csp-violation-report', to: 'csp_violation_reports#create'

  get 'kanban', to: 'tasks#kanban', as: :kanban
  get 'kanban/tasks', to: 'tasks#kanban_tasks', as: :kanban_tasks

  # Reports: setup (filter projects, select stats) and analysis (summary + breakdowns, optional PDF)
  # Report config (project_ids, stats) is stored in session to keep analysis URL short.
  get 'reports', to: 'reports#index', as: :reports
  post 'reports/set_config', to: 'reports#set_config', as: :set_report_config
  get 'reports/analysis', to: 'reports#analysis', as: :reports_analysis
  get 'task_insights', to: 'task_insights#index', as: :task_insights
  post 'task_insights', to: 'task_insights#create'
  get 'task_insights/status/:run_id', to: 'task_insights#status', as: :task_insights_status
  get 'task_insights/ollama_health', to: 'task_insights#ollama_health', as: :task_insights_ollama_health
end
