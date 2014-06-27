class MainSite
  def self.matches?(request)
    request.subdomain.blank? || request.subdomain == 'www'
  end
end

Saas::Application.routes.draw do

  devise_for :saas_admins
  mount RailsAdmin::Engine => '/saas_admin', :as => 'rails_admin'

  # Routes for the public site
  constraints MainSite do
    # Homepage
    get '/' => "content#index"

    # Other content routes, like privacy policy, about us, etc.
    %w(about privacy).each do |page|
      get page => "content##{page}"
    end

    # Account Signup Routes
    get '/signup' => 'accounts#plans', :as => 'plans'
    get '/signup/d/:discount' => 'accounts#plans'
    get '/signup/thanks' => 'accounts#thanks', :as => 'thanks'
    post '/signup/create/:discount' => 'accounts#create', :as => 'create', :defaults => { :discount => nil }
    get '/signup/:plan/:discount' => 'accounts#new'
    get '/signup/:plan' => 'accounts#new', :as => 'new_account'

  end

  root :to => "accounts#dashboard"

  devise_for :users

  #
  # Account / User Management Routes
  #
  resources :users
  resource :account do
    member do
      get :dashboard, :thanks, :plans, :canceled
      match 'billing' => "accounts#billing", via: [ :get, :post ]
      match 'plan' => "accounts#plan", via: [ :get, :post ]
      match 'cancel' => "accounts#cancel", via: [ :get, :post ]
    end
  end
  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  # root 'welcome#index'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
