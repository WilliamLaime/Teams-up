# Preview accessible en développement à l'URL :
# http://localhost:3000/rails/mailers/waitlist_mailer/launch_announcement
class WaitlistMailerPreview < ActionMailer::Preview
  def launch_announcement
    WaitlistMailer.launch_announcement("exemple@email.com")
  end
end
