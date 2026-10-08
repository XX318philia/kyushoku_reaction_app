class KindergartenSessionsController < ApplicationController
  def new
  end

  def create
    user = authenticate_user(login_id: params[:login_id], password: params[:password])

    if user&.kindergarten?
      log_in(user)
      redirect_to new_reaction_path, status: :see_other
    else
      flash.now[:alert] = "ログインIDまたはパスワードが正しくありません"
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    log_out
    redirect_to kindergarten_login_path, status: :see_other
  end
end
