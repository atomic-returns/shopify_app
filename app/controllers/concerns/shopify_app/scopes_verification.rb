# frozen_string_literal: true

module ShopifyApp
  module ScopesVerification
    extend ActiveSupport::Concern
    include ScopeUtilities

    included do
      before_action do
        login_on_scope_changes(current_merchant_scopes, configuration_scopes)
      end
    end

    protected

    def login_on_scope_changes(current_merchant_scopes, configuration_scopes)
      redirect_to(shop_login) if scopes_configuration_mismatch?(current_merchant_scopes, configuration_scopes)
    end

    def current_merchant_scopes
      measure_performance "fetch_scopes_via_rest.txt" do
        #installed_access_scopes_via_db
        #installed_access_scopes_via_graphql
        installed_access_scopes_via_rest
      end
    end

    def configuration_scopes
      ShopifyApp.configuration.scope
    end

    private

    def measure_performance(filename)
      start = Time.now
      access_scopes = yield
      finish = Time.now

      f = File.new(filename, 'a')
      f << "#{finish - start}\n"
      f.close

      access_scopes
    end

    def installed_access_scopes_via_db
      ShopifyApp::SessionRepository.retrieve_shop_scopes(current_shopify_domain)
    end

    def installed_access_scopes_via_rest
      begin
        shop_session = ShopifyApp::SessionRepository.retrieve_shop_session_by_shopify_domain(current_shopify_domain)
        ShopifyAPI::Base.activate_session(shop_session)

        ShopifyAPI::AccessScope.find(:all).map(&:handle)
      ensure
        ShopifyAPI::Base.clear_session
      end
    end

    def installed_access_scopes_via_graphql
      # This is identical to LoginProtection right now
      shop_session = ShopifyApp::SessionRepository.retrieve_shop_session_by_shopify_domain(current_shopify_domain)
      ShopifyAPI::Base.activate_session(shop_session)

      client = ShopifyAPI::GraphQL.client(ShopifyApp.configuration.api_version)

      # This is the real work
      result = client.query(client.parse(installation_query))

      # This looks like a ScopeUtilities method
      result.data.app_installation.access_scopes.map { |access_scope| access_scope.handle }
    end

    def installation_query
      query = <<-GRAPHQL
        {
          appInstallation {
            accessScopes {
              handle
            }
          }
        }
      GRAPHQL
    end

    def current_shopify_domain
      return if params[:shop].blank?
      ShopifyApp::Utils.sanitize_shop_domain(params[:shop])
    end

    def shop_login
      ShopifyApp::Utils.shop_login_url(shop: params[:shop], return_to: request.fullpath)
    end
  end
end
