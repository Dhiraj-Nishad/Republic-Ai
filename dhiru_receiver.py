import http.server
import os

class MyHandler(http.server.SimpleHTTPRequestHandler):
    def do_PUT(self):
        # File ka naam path se nikalna
        filename = os.path.basename(self.path)
        file_path = os.path.join('/var/www/republic', filename)
        
        # Data read karke file mein save karna
        content_length = int(self.headers['Content-Length'])
        with open(file_path, 'wb') as f:
            f.write(self.rfile.read(content_length))
        
        self.send_response(201)
        self.end_headers()
        print(f"✅ Received: {filename}")

# Port 80 par server chalu karna
os.chdir('/var/www/republic')
server = http.server.HTTPServer(('0.0.0.0', 80), MyHandler)
print("🚀 Dhiru Receiver started on Port 80...")
server.serve_forever()
