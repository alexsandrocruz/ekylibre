class Pasteque::V5::UsersController < Pasteque::V5::BaseController
  manage_restfully only: [:index, :show]

  def update_password
    user = User.find_for_authentication(email: params[:user])
    old_password = params[:oldPwd]
    new_password = params[:newPwd]
    if user and user.valid_password?(old_password)
      user.password = new_password
      user.password_confirmation = new_password
      render json: user.save!
    else
      render json: false
    end
  end


end
