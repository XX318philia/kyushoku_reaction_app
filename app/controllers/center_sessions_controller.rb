class CenterSessionsController < ApplicationController
  def new
  end

  def create
    user = authenticate_user(login_id: params[:login_id], password: params[:password])

    if user&.center?
      log_in(user)
      redirect_to root_path, status: :see_other
    else
      flash.now[:alert] = "ログインIDまたはパスワードが正しくありません"
      render :new, status: :unprocessable_content
    end
  end
end
