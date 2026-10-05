class DishesController < ApplicationController
  def new
    @dish = Dish.new
  end

  def create
    @dish = Dish.new(dish_params)

    if @dish.save
      redirect_to new_dish_path, status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def dish_params
    params.require(:dish).permit(:name, :category)
  end
end
