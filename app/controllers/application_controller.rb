class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :logged_in?, :kindergarten_user?, :center_user?

  private

  def require_kindergarten_user
    return redirect_to kindergarten_login_path, status: :see_other unless logged_in?

    redirect_to center_reaction_results_path, alert: "このページにはアクセスできません", status: :see_other unless kindergarten_user?
  end

  def require_center_user
    return redirect_to center_login_path, status: :see_other unless logged_in?

    redirect_to new_reaction_path, alert: "このページにはアクセスできません", status: :see_other unless center_user?
  end

  def authenticate_user(login_id:, password:)
    User.authenticate_by(login_id: login_id, password: password)
  end

  def log_in(user)
    reset_session
    session[:user_id] = user.id
    @current_user = user
  end

  def log_out
    reset_session
    @current_user = nil
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def kindergarten_user?
    current_user&.kindergarten? || false
  end

  def center_user?
    current_user&.center? || false
  end
end
