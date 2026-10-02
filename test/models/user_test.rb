require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @kindergarten = Kindergarten.create!(name: "さくら幼稚園")
    @user = User.new(login_id: "sakura", password: "password", role: :kindergarten, kindergarten: @kindergarten)
  end

  test "saves a kindergarten user with a password digest and timestamps" do
    assert @user.save
    @user.reload

    assert_equal @kindergarten, @user.kindergarten
    assert_not_equal "password", @user.password_digest
    assert BCrypt::Password.new(@user.password_digest).is_password?("password")
    assert_not User.column_names.include?("password")
    assert_not_nil @user.created_at
    assert_not_nil @user.updated_at
  end

  test "authenticates only with the correct password after loading from the database" do
    @user.save!
    user = User.find(@user.id)

    assert_equal user, user.authenticate("password")
    assert_equal false, user.authenticate("wrong-password")
  end

  test "does not save a new user without a password" do
    [ nil, "" ].each do |password|
      user = User.new(login_id: "center", role: :center, password: password)

      assert_not user.save
      assert user.errors.of_kind?(:password, :blank)
    end
  end

  test "does not add a custom minimum password length" do
    @user.password = "a"

    assert @user.save
    assert_equal @user, @user.authenticate("a")
  end

  test "does not enable password reset tokens" do
    assert_not @user.respond_to?(:password_reset_token)
    assert_not User.respond_to?(:find_by_password_reset_token)
  end

  test "does not save a blank login id" do
    [ nil, "", "   ", "\t\n", "　" ].each do |login_id|
      @user.login_id = login_id

      assert_not @user.save
      assert @user.errors.of_kind?(:login_id, :blank)
    end
  end

  test "does not save duplicate login ids" do
    @user.save!
    user = User.new(login_id: @user.login_id, password: "password", role: :center)

    assert_not user.save
    assert user.errors.of_kind?(:login_id, :taken)
  end

  test "preserves login id case whitespace and characters" do
    [ "Center", "center", " Center ", "給食センター@1" ].each do |login_id|
      user = User.create!(login_id: login_id, password: "password", role: :center)

      assert_equal login_id, user.reload.login_id
    end
  end

  test "stores roles as strings" do
    assert_equal({ "kindergarten" => "kindergarten", "center" => "center" }, User.roles)
    @user.save!
    center_user = User.create!(login_id: "center", password: "password", role: :center)

    assert @user.reload.kindergarten?
    assert center_user.reload.center?
    assert_equal "kindergarten", @user.role_before_type_cast
    assert_equal "center", center_user.role_before_type_cast
  end

  test "rejects missing and invalid roles with validation errors" do
    [ nil, "", "invalid" ].each do |role|
      @user.role = role

      assert_not @user.save
      assert @user.errors.of_kind?(:role, :inclusion)
    end
  end

  test "does not save a kindergarten user without a kindergarten" do
    @user.kindergarten = nil

    assert_not @user.save
    assert @user.errors.of_kind?(:kindergarten, :blank)
  end

  test "does not save a kindergarten user with a nonexistent kindergarten" do
    @user.kindergarten_id = Kindergarten.maximum(:id) + 1

    assert_not @user.save
    assert @user.errors.of_kind?(:kindergarten, :blank)
  end

  test "does not save a center user belonging to a kindergarten" do
    @user.role = :center

    assert_not @user.save
    assert @user.errors.of_kind?(:kindergarten, :present)
  end

  test "does not save a center user with a nonexistent kindergarten id" do
    @user.role = :center
    @user.kindergarten_id = Kindergarten.maximum(:id) + 1

    assert_not @user.save
    assert @user.errors.of_kind?(:kindergarten_id, :present)
  end

  test "does not save a center user with an unsaved kindergarten" do
    @user.role = :center
    @user.kindergarten = Kindergarten.new(name: "すみれ幼稚園")

    assert_no_difference "Kindergarten.count" do
      assert_not @user.save
    end
    assert @user.errors.of_kind?(:kindergarten, :present)
  end

  test "does not save multiple users for the same kindergarten" do
    @user.save!
    user = User.new(login_id: "other", password: "password", role: :kindergarten, kindergarten: @kindergarten)

    assert_not user.save
    assert user.errors.of_kind?(:kindergarten_id, :taken)
  end

  test "saves multiple center users without a kindergarten" do
    2.times do |index|
      user = User.new(login_id: "center#{index}", password: "password", role: :center)

      assert user.save
      assert_nil user.reload.kindergarten_id
    end
  end

  test "rejects changing a kindergarten user to center without removing its kindergarten" do
    @user.save!

    assert_not @user.update(role: :center)
    assert @user.errors.of_kind?(:kindergarten, :present)
    assert @user.reload.kindergarten?
  end

  test "rejects removing the kindergarten from a kindergarten user" do
    @user.save!

    assert_not @user.update(kindergarten: nil)
    assert @user.errors.of_kind?(:kindergarten, :blank)
    assert_equal @kindergarten, @user.reload.kindergarten
  end

  test "rejects changing a center user to kindergarten without assigning a kindergarten" do
    user = User.create!(login_id: "center", password: "password", role: :center)

    assert_not user.update(role: :kindergarten)
    assert user.errors.of_kind?(:kindergarten, :blank)
    assert user.reload.center?
  end

  test "rejects assigning a kindergarten to a center user" do
    user = User.create!(login_id: "center", password: "password", role: :center)

    assert_not user.update(kindergarten: @kindergarten)
    assert user.errors.of_kind?(:kindergarten, :present)
    assert_nil user.reload.kindergarten_id
  end

  test "allows consistent role and kindergarten changes without reentering the password" do
    @user.save!
    user = User.find(@user.id)
    digest = user.password_digest

    assert user.update(role: :center, kindergarten: nil)
    assert user.reload.center?
    assert_nil user.kindergarten_id
    assert user.update(role: :kindergarten, kindergarten: @kindergarten)
    assert user.reload.kindergarten?
    assert_equal @kindergarten, user.kindergarten
    assert_equal digest, user.password_digest
  end

  test "allows moving a user only to a kindergarten without another user" do
    @user.save!
    other_kindergarten = Kindergarten.create!(name: "すみれ幼稚園")
    other_user = User.create!(login_id: "sumire", password: "password", role: :kindergarten, kindergarten: other_kindergarten)

    assert_not @user.update(kindergarten: other_kindergarten)
    assert @user.errors.of_kind?(:kindergarten_id, :taken)
    assert_equal @kindergarten, @user.reload.kindergarten

    other_user.update!(role: :center, kindergarten: nil)
    assert @user.update(kindergarten: other_kindergarten)
    assert_equal other_kindergarten, @user.reload.kindergarten
  end

  test "database rejects null login id password digest and role without validation" do
    [ :login_id, :password_digest, :role ].each do |attribute|
      assert_raises ActiveRecord::NotNullViolation do
        User.transaction(requires_new: true) do
          user = User.new(login_id: "center", password: "password", role: :center)
          user.public_send("#{attribute}=", nil)
          user.save!(validate: false)
        end
      end
    end
  end

  test "database rejects duplicate login ids without validation" do
    @user.save!

    assert_raises ActiveRecord::RecordNotUnique do
      User.transaction(requires_new: true) do
        User.new(login_id: @user.login_id, password: "password", role: :center).save!(validate: false)
      end
    end
  end

  test "database rejects duplicate kindergarten ids without validation" do
    @user.save!

    assert_raises ActiveRecord::RecordNotUnique do
      User.transaction(requires_new: true) do
        User.new(login_id: "other", password: "password", role: :kindergarten, kindergarten: @kindergarten).save!(validate: false)
      end
    end
  end

  test "database rejects nonexistent kindergarten ids without validation" do
    @user.kindergarten_id = Kindergarten.maximum(:id) + 1

    assert_raises ActiveRecord::InvalidForeignKey do
      User.transaction(requires_new: true) do
        @user.save!(validate: false)
      end
    end
  end
end
