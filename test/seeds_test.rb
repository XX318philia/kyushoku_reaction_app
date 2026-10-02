require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "creates demo users kindergarten and classrooms with working passwords" do
    assert_difference({ "User.count" => 2, "Kindergarten.count" => 1, "Classroom.count" => 3 }) do
      load_seeds
    end

    center_user = User.find_by!(login_id: "center_demo")
    kindergarten_user = User.find_by!(login_id: "kindergarten_demo")
    kindergarten = kindergarten_user.kindergarten

    assert center_user.center?
    assert_nil center_user.kindergarten_id
    assert kindergarten_user.kindergarten?
    assert_equal "サンプル幼稚園", kindergarten.name
    assert_equal [ "さくら", "うめ", "チューリップ" ].sort, kindergarten.classrooms.pluck(:name).sort

    [ [ center_user, "demo-c-2026" ], [ kindergarten_user, "demo-k-2026" ] ].each do |user, password|
      assert_not_equal password, user.password_digest
      assert_equal user, user.authenticate(password)
      assert_equal false, user.authenticate("wrong-password")
    end
  end

  test "repeated runs preserve the ids and counts of all seed records" do
    load_seeds
    ids = [ User.order(:id).ids, Kindergarten.order(:id).ids, Classroom.order(:id).ids ]

    assert_no_difference [ "User.count", "Kindergarten.count", "Classroom.count" ] do
      2.times { load_seeds }
    end

    assert_equal ids, [ User.order(:id).ids, Kindergarten.order(:id).ids, Classroom.order(:id).ids ]
  end

  test "does not reuse same named kindergartens or change unrelated records" do
    existing_kindergarten = Kindergarten.create!(name: "サンプル幼稚園")
    unassigned_kindergarten = Kindergarten.create!(name: "サンプル幼稚園")
    existing_classroom = existing_kindergarten.classrooms.create!(name: "さくら")
    existing_user = User.create!(login_id: "existing", role: :kindergarten,
      password: "existing-password", kindergarten: existing_kindergarten)
    existing_center = User.create!(login_id: "existing_center", role: :center, password: "existing-password")
    records = [ existing_kindergarten, unassigned_kindergarten, existing_classroom, existing_user, existing_center ]
    attributes = records.map(&:attributes)

    assert_difference({ "User.count" => 2, "Kindergarten.count" => 1, "Classroom.count" => 3 }) do
      load_seeds
    end
    load_seeds

    seed_kindergarten = User.find_by!(login_id: "kindergarten_demo").kindergarten
    assert_not_includes [ existing_kindergarten.id, unassigned_kindergarten.id ], seed_kindergarten.id
    assert_equal attributes, records.map { |record| record.reload.attributes }
  end

  test "restores demo passwords center role and kindergarten name on rerun" do
    load_seeds
    center_user = User.find_by!(login_id: "center_demo")
    kindergarten_user = User.find_by!(login_id: "kindergarten_demo")
    kindergarten = kindergarten_user.kindergarten
    other_kindergarten = Kindergarten.create!(name: "別の幼稚園")
    other_attributes = other_kindergarten.attributes
    center_user.update!(role: :kindergarten, kindergarten: other_kindergarten, password: "changed-center")
    kindergarten_user.update!(password: "changed-kindergarten")
    kindergarten.update!(name: "変更後の幼稚園名")

    assert_no_difference [ "User.count", "Kindergarten.count", "Classroom.count" ] do
      load_seeds
    end

    assert center_user.reload.center?
    assert_nil center_user.kindergarten_id
    assert_equal center_user, center_user.authenticate("demo-c-2026")
    assert kindergarten_user.reload.kindergarten?
    assert_equal kindergarten_user, kindergarten_user.authenticate("demo-k-2026")
    assert_equal kindergarten.id, kindergarten_user.kindergarten_id
    assert_equal "サンプル幼稚園", kindergarten.reload.name
    assert_equal other_attributes, other_kindergarten.reload.attributes
  end

  test "sets the kindergarten demo role and association when it exists as a center user" do
    user = User.create!(login_id: "kindergarten_demo", role: :center, password: "old-password")

    assert_difference({ "User.count" => 1, "Kindergarten.count" => 1, "Classroom.count" => 3 }) do
      load_seeds
    end

    assert user.reload.kindergarten?
    assert_equal "サンプル幼稚園", user.kindergarten.name
    assert_equal user, user.authenticate("demo-k-2026")
  end

  test "keeps unrelated classrooms belonging to the seed kindergarten" do
    load_seeds
    kindergarten = User.find_by!(login_id: "kindergarten_demo").kindergarten
    classroom = kindergarten.classrooms.create!(name: "ひまわり")
    attributes = classroom.attributes

    assert_no_difference "Classroom.count" do
      load_seeds
    end

    assert_equal attributes, classroom.reload.attributes
  end

  private

  def load_seeds
    load Rails.root.join("db/seeds.rb")
  end
end
