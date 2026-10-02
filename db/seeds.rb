# 開発環境・MVP公開デモ環境で使用する架空の初期データ。
ActiveRecord::Base.transaction do
  center_user = User.find_or_initialize_by(login_id: "center_demo")
  center_user.update!(role: :center, password: "demo-c-2026", kindergarten: nil)

  kindergarten_user = User.find_or_initialize_by(login_id: "kindergarten_demo")
  # 同名の既存幼稚園を再利用せず、seed対象Userとの関連で識別する。
  kindergarten = kindergarten_user.kindergarten || Kindergarten.new
  kindergarten.update!(name: "サンプル幼稚園")
  kindergarten_user.update!(role: :kindergarten, password: "demo-k-2026", kindergarten: kindergarten)

  [ "さくら", "うめ", "チューリップ" ].each do |name|
    kindergarten.classrooms.find_or_create_by!(name: name)
  end
end
