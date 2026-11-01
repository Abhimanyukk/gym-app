Optional public server certificate only; never copy server.key here.
Copy the Pi's server.crt here before building, then use:
--dart-define=API_CERT_ASSET=assets/certificates/server.crt
For web, trust the certificate in the browser instead.
