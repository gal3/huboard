require 'sinatra'
require 'sinatra/content_for'
require 'stripe'

class Huboard
  class Accounts < HuboardApplication

    def initialize(app = nil)
      super(app)
      @parameters = {}
    end

    if File.exists? "#{File.dirname(__FILE__)}/../.settings"
      puts "settings file"
      token_file =  File.new("#{File.dirname(__FILE__)}/../.settings")
      # TODO: read this from a yaml
      eval(token_file.read) 
    elsif ENV['STRIPE_API']
      set :stripe_key, ENV['STRIPE_API']
      set :stripe_publishable_key, ENV['STRIPE_PUBLISHABLE_API']
    else
      raise "Configuration information not found: you need to provide a .settings file or ENV variables"
    end

    Stripe.api_key = settings.stripe_key

    before do
      protected!
    end

    helpers do
      def protected! 
        return current_user if authenticated? :private
        authenticate! :scope => :private
      end

    end


    get "/profile/?" do

      @user = gh.user
      @orgs = gh.orgs

      erb :accounts, :layout => :ember_layout
    end

    put "/profile/:name/card/?" do
      user = gh.users params[:name]

      docs = couch.customers.findPlanById user.id

      if docs.rows.any?
        plan_doc = docs.rows.first.value

        customer = Stripe::Customer.retrieve(plan_doc.stripe.customer.id)

        customer.card = params[:card][:id]
        updated = customer.save

        plan_doc.stripe.customer = updated

        couch.customers.save plan_doc

        json success: true, message: "Card updated", card: updated["cards"]["data"].first
      else
        json success: false, message: "Unable to find plan"
      end

    end
    delete "/profile/:name/plans/:plan_id/?" do
      user = gh.users params[:name]

      docs = couch.customers.findPlanById user.id

      if docs.rows.any?
        plan_doc = docs.rows.first.value

        customer = Stripe::Customer.retrieve(plan_doc.stripe.customer.id)

        customer.cancel_subscription at_period_end: false
        customer.delete

        couch.customers.delete! plan_doc

        json success: true, message: "Sorry to see you go"
      else
        json success: false, message: "Unable to find plan"
      end
    end

    post "/charge/:id/?" do 

      puts params

      customer = Stripe::Customer.create(
        :email => params[:email],
        :card  => params[:card][:id],
        :plan =>  params[:plan][:id]
      )

      user = gh.user
      account = gh.users(params[:id])

      couch.customers.save({
         "id" => customer.id,
         github: {
          :user => user.to_hash,
          :account => account.to_hash
         },
         stripe: {
            customer: customer,
            plan: {
              plan_id: params[:plan][:plan_id]
            }
         }
      })

      json :success => true, card: customer["cards"]["data"].first
    end

    helpers Sinatra::ContentFor
  end
end
