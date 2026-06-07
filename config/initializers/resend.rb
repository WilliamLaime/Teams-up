# Initializer Resend — configure la clé API au démarrage de l'application.
# La clé est stockée dans la variable d'environnement RESEND_API_KEY
# (définie sur Railway dans les variables du projet).
# Sans cette ligne, la gem Resend lève une erreur "Make sure your API Key is set".
Resend.api_key = ENV["RESEND_API_KEY"]
