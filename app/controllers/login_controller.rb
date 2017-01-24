class LoginController < ApplicationController
  include SearchesHelper
  include Concerns::Logging

  before_action :reject_crawler, only: %i(sign_in sign_out)
  before_action :push_referer, only: %i(welcome sign_in sign_out)
  before_action :create_search_log, only: %i(welcome sign_in sign_out)

  # GET /welcome
  def welcome
    redirect_to root_path, notice: t('dictionary.signed_in') if user_signed_in?
    @redirect_path = params[:redirect_path].presence || root_path
  end

  # GET /sign_in
  def sign_in
    session[:sign_in_from] = request.url
    vertical = params[:bottom] ? 'bottom' : 'top'
    session[:sign_in_via] = params[:via] ? "#{params[:via]}_#{vertical}" : ''
    session[:sign_in_follow] = 'true' == params[:follow] ? 'true' : 'false'
    session[:redirect_path] = params[:redirect_path].presence || root_path
    redirect_to '/users/auth/twitter'
  end

  # GET /sign_out
  def sign_out
    redirect_to destroy_user_session_path
  end
end
