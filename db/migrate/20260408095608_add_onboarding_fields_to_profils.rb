class AddOnboardingFieldsToProfils < ActiveRecord::Migration[8.1]
  def change
    add_column :profils, :onboarding_shown_at, :datetime
    add_column :profils, :profile_reminder_dismissed_at, :datetime
  end
end
